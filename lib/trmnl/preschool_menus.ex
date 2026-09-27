defmodule Trmnl.PreschoolMenus do
  alias Trmnl.{Repo, PreschoolMenu, PreschoolParser, MenuAI}
  @source "https://przedszkole123.dlaprzedszkoli.eu/?m=strona&id=30"
  def source, do: @source
  def status, do: Repo.get(PreschoolMenu, 1) || %PreschoolMenu{id: 1}

  def save_settings(attrs) do
    changeset =
      status()
      |> Ecto.Changeset.cast(attrs, [:enabled, :mode])
      |> Ecto.Changeset.validate_required([:mode, :enabled])
      |> Ecto.Changeset.validate_inclusion(:mode, ["plain", "openrouter"])

    if Ecto.Changeset.get_field(changeset, :mode) == "openrouter" and not MenuAI.configured?() do
      {:error, :missing_key}
    else
      Repo.insert_or_update(changeset)
    end
  end

  def enqueue do
    Trmnl.PreschoolMenuWorker.new(%{"manual" => true}) |> Oban.insert()
  end

  def sync(manual? \\ false) do
    result =
      Repo.transaction(
        fn ->
          # Serialize manual and scheduled imports, including the unchanged-source check.
          Repo.query!("SELECT pg_advisory_xact_lock(73401926)")
          menu = status()
          if manual? or menu.enabled, do: import_menu(menu), else: :disabled
        end,
        timeout: 90_000
      )

    case result do
      {:ok, {:error, _} = error} -> error
      other -> other
    end
  end

  defp import_menu(menu) do
    with {:ok, rows} <- fetch() do
      input = if menu.mode == "openrouter", do: %{model: MenuAI.model(), days: rows}, else: rows
      hash = :crypto.hash(:sha256, Jason.encode!(input)) |> Base.encode16(case: :lower)

      if menu.source_hash == hash and menu.imported_mode == menu.mode do
        save!(menu, checked_at: now(), error: nil)
        :unchanged
      else
        case extract(rows, menu.mode) do
          {:ok, days} ->
            save!(menu,
              days: days,
              source_hash: hash,
              imported_mode: menu.mode,
              checked_at: now(),
              imported_at: now(),
              error: nil
            )

            case Oban.insert(Trmnl.RefreshWorker.new(%{})) do
              {:ok, _} -> :updated
              {:error, _} -> Repo.rollback(:refresh_failed)
            end

          {:error, reason} ->
            fail(menu, reason)
        end
      end
    else
      {:error, reason} -> fail(menu, reason)
    end
  end

  defp fetch do
    options = [
      url: @source,
      retry: false,
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000],
      headers: [
        {"user-agent", "TRMNL-Creator/0.1 https://github.com/iskandiar/trmnl-creator-elixir"}
      ]
    ]

    case Req.get(
           Keyword.merge(options, Application.get_env(:trmnl, :menu_source_req_options, []))
         ) do
      {:ok, %Req.Response{status: 200, body: html}} -> PreschoolParser.parse(html)
      _ -> {:error, :source_failed}
    end
  rescue
    _ -> {:error, :source_failed}
  end

  defp extract(rows, "plain"), do: {:ok, rows}
  defp extract(rows, "openrouter"), do: MenuAI.summarize(rows)

  defp fail(menu, reason) do
    message =
      case reason do
        :missing_key ->
          "Brak OPENROUTER_API_KEY. Wybierz import bez AI lub skonfiguruj klucz."

        :ai_failed ->
          "Nie udało się przetworzyć odpowiedzi OpenRouter. Spróbuj ponownie lub wybierz import bez AI."

        {:ai_http, 429} ->
          "OpenRouter: przekroczony limit zapytań lub brak dostępnej kwoty (HTTP 429). Sprawdź limit projektu w OpenRouter i spróbuj później lub wybierz import bez AI."

        {:ai_http, status} when status in [401, 403] ->
          "OpenRouter: odmowa dostępu (HTTP #{status}). Sprawdź OPENROUTER_API_KEY oraz uprawnienia i ograniczenia klucza w koncie OpenRouter."

        {:ai_http, 400} ->
          "OpenRouter: odrzucone żądanie (HTTP 400). Sprawdź poprawność OPENROUTER_API_KEY i dostępność API dla projektu."

        {:ai_http, 402} ->
          "OpenRouter: brak środków lub przekroczony limit wydatków klucza (HTTP 402). Doładuj konto lub wybierz import bez AI."

        {:ai_http, 404} ->
          "OpenRouter: model lub endpoint jest niedostępny (HTTP 404). Wymagana jest aktualizacja konfiguracji modelu."

        {:ai_http, status} ->
          "OpenRouter: błąd usługi (HTTP #{status}). Spróbuj ponownie później lub wybierz import bez AI."

        :ai_connection ->
          "Nie udało się połączyć z OpenRouter lub upłynął czas oczekiwania. Sprawdź połączenie serwera z internetem i spróbuj ponownie."

        :ai_invalid_json ->
          "OpenRouter zwróciło niepoprawny JSON. Spróbuj ponownie lub wybierz import bez AI."

        :ai_invalid_menu ->
          "Odpowiedź OpenRouter nie pasuje do oczekiwanego formatu: brak ukończonej odpowiedzi tekstowej. Spróbuj ponownie lub wybierz import bez AI."

        {:ai_invalid_menu, :shape} ->
          "OpenRouter: niepoprawna struktura JSON jadłospisu. Oczekiwano obiektu z listą dni w polu days. Spróbuj ponownie lub wybierz import bez AI."

        {:ai_invalid_menu, :dates} ->
          "OpenRouter: daty nie zgadzają się ze źródłem — model pominął, powtórzył lub zmienił dzień. Spróbuj ponownie lub wybierz import bez AI."

        {:ai_invalid_menu, :meals} ->
          "OpenRouter: co najmniej jeden posiłek jest pusty, pominięty, nie jest tekstem lub przekracza 5000 znaków. Spróbuj ponownie lub wybierz import bez AI."

        :ai_truncated ->
          "OpenRouter przerwało odpowiedź po osiągnięciu limitu długości. Spróbuj ponownie lub wybierz import bez AI."

        :ai_blocked ->
          "OpenRouter zablokowało przetwarzanie jadłospisu. Wybierz import bez AI."

        :invalid_menu ->
          "Nie rozpoznano pełnego jadłospisu na stronie. Sprawdź źródło."

        _ ->
          "Nie udało się pobrać jadłospisu. Spróbuj ponownie później."
      end

    save!(menu, checked_at: now(), error: message)
    {:error, message}
  end

  defp save!(menu, attrs), do: menu |> Ecto.Changeset.change(attrs) |> Repo.insert_or_update!()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
