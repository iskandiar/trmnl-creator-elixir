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
            <option value="openrouter" selected={@form[:mode].value == "openrouter"}>
              OpenRouter · GPT-4.1 mini · krótsze opisy
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
          do: "Klucz OpenRouter jest skonfigurowany.",
          else:
            "Opcjonalne AI: utwórz klucz w OpenRouter, ustaw OPENROUTER_API_KEY w konfiguracji serwera i uruchom aplikację ponownie."}
        <a href="https://openrouter.ai/settings/keys" target="_blank" rel="noopener noreferrer">OpenRouter</a>
      </p>
      <p class="hint">
        Model: {Trmnl.MenuAI.model()}. Wymaga środków na koncie OpenRouter. Orientacyjny koszt: poniżej 0,01 USD za tygodniowy jadłospis, zależnie od długości. Do AI trafia tylko publiczny jadłospis. Niezmieniona strona i model nie wywołują ponownie AI.
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
