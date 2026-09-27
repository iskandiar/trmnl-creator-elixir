defmodule TrmnlWeb.PreschoolSettings do
  use TrmnlWeb, :html

  attr :menu, :any, required: true
  attr :form, :any, required: true
  attr :ai_configured, :boolean, required: true
  attr :streams, :any, required: true

  def panel(assigns) do
    ~H"""
    <section id="preschool-settings" class="panel">
      <h2>Jadłospis · Przedszkole 123</h2>
      <p>
        <a href={Trmnl.PreschoolMenus.source()} target="_blank" rel="noopener noreferrer">Otwórz jadłospis przedszkola</a>
      </p>
      <p class="hint">
        Import śniadań, obiadów i podwieczorków z datami podanymi na stronie. Dodaj blok „Jadłospis przedszkola”, aby pokazać je na ekranie.
      </p>
      <.form for={@form} id="preschool-import-form" phx-submit="preschool:settings">
        <label for="preschool-mode">
          Sposób importu
          <select id="preschool-mode" name={@form[:mode].name}>
            <option value="plain" selected={@form[:mode].value == "plain"}>
              Bez AI · bezpłatnie, bez klucza
            </option>
            <option value="gemini" selected={@form[:mode].value == "gemini"}>
              Gemini Flash-Lite · krótsze opisy
            </option>
          </select>
        </label>
        <input type="hidden" name={@form[:enabled].name} value="false" />
        <label class="check"><input
          id="preschool-auto"
          type="checkbox"
          name={@form[:enabled].name}
          value="true"
          checked={@form[:enabled].value in [true, "true"]}
        />Importuj co niedzielę o 20:00 (czas Warszawy)</label>
        <button id="preschool-save" type="submit">Zapisz ustawienia importu</button>
      </.form>
      <p id="preschool-ai-status" class="hint">
        {if @ai_configured,
          do: "Klucz Gemini jest skonfigurowany.",
          else:
            "Opcjonalne AI: utwórz klucz w Google AI Studio, ustaw GEMINI_API_KEY w konfiguracji serwera i uruchom aplikację ponownie."}
        <a href="https://aistudio.google.com/apikey" target="_blank" rel="noopener noreferrer">Google AI Studio</a>
      </p>
      <p class="hint">
        Model: gemini-2.5-flash-lite. Aby korzystać bez opłat, użyj projektu na darmowym planie bez włączania płatnego rozliczania. Obowiązują limity Google. Do AI trafia tylko publiczny jadłospis. Niezmieniona strona nie wywołuje ponownie AI.
      </p>
      <button id="preschool-import" type="button" phx-click="preschool:import">Pobierz jadłospis teraz</button>
      <p id="preschool-status" class="hint">
        Ostatnia próba: {time(@menu.checked_at)} · Ostatni import: {time(@menu.imported_at)}
      </p>
      <p :if={@menu.error} id="preschool-error" class="error">
        {@menu.error} Poprzedni jadłospis pozostaje zapisany.
      </p>
      <p :if={@menu.days == []} id="preschool-empty" class="muted">
        Nie zaimportowano jeszcze jadłospisu.
      </p>
      <div id="preschool-days" phx-update="stream">
        <article :for={{id, day} <- @streams.preschool_days} id={id} class="family-row">
          <div>
            <strong>{day["date"]}</strong>
            <p :for={
              {field, label} <- [
                {"breakfast", "Śniadanie"},
                {"lunch", "Obiad"},
                {"snack", "Podwieczorek"}
              ]
            }>
              <b>{label}:</b> {day[field]}
            </p>
            <details :if={day["original"]}>
              <summary>Pełny tekst ze źródła</summary><p :for={field <- ~w(breakfast lunch snack)}>
                {day["original"][field]}
              </p>
            </details>
          </div>
        </article>
      </div>
    </section>
    """
  end

  defp time(nil), do: "brak"

  defp time(value),
    do: value |> DateTime.shift_zone!("Europe/Warsaw") |> Calendar.strftime("%d.%m.%Y %H:%M")
end
