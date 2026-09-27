defmodule TrmnlWeb.FamilyContent do
  use TrmnlWeb, :html
  alias Trmnl.{Family, FamilySchedule}

  attr :kind, :string, required: true
  attr :item, :any, required: true
  attr :form, :any, required: true
  attr :form_epoch, :integer, required: true
  attr :streams, :any, required: true
  attr :empty, :boolean, required: true
  attr :notice, :any, default: nil
  attr :today, :any, required: true

  def panel(assigns) do
    ~H"""
    <section class="family-content">
      <div class="panel-heading">
        <div>
          <h2>Dom pod kontrolą</h2><p class="muted">
            Zarządzaj treścią tutaj. Rozmieszczenie i wygląd bloków zmienisz w zakładce Układ.
          </p>
        </div>
      </div>
      <nav class="module-tabs" aria-label="Moduły rodzinne">
        <button
          :for={{key, label} <- Family.labels()}
          id={"module-#{key}"}
          type="button"
          phx-click="family:module"
          phx-value-kind={key}
          aria-pressed={to_string(@kind == key)}
          class={[@kind == key && "active"]}
        >{label}</button>
      </nav>
      <p :if={@notice} id="family-notice" class="notice" role="status">{@notice}</p>
      <div class="family-columns">
        <section class="panel family-form-panel">
          <div class="panel-heading">
            <h2>{if @item.id, do: "Edytuj wpis", else: "Nowy wpis"}</h2><button
              :if={@item.id}
              id="family-new"
              type="button"
              phx-click="family:new"
            >Anuluj edycję</button>
          </div>
          <p class="muted">{description(@kind)}</p>
          <.form for={@form} id="family-form" phx-submit="family:save">
            <div id={"family-fields-#{@form_epoch}"}>
              <.field field={@form[:title]} label={title_label(@kind)} required maxlength="120" />
              <div class="form-grid">
                <.field
                  :if={@kind != "today_tomorrow"}
                  field={@form[:date]}
                  label={date_label(@kind)}
                  type="date"
                  required={@kind in ~w(dinner countdowns)}
                />
                <.field
                  :if={@kind == "dinner"}
                  field={@form[:time]}
                  label="Godzina (opcjonalna)"
                  type="time"
                />
                <.field
                  :if={@kind == "family_note"}
                  field={@form[:end_date]}
                  label="Wyświetlaj do (opcjonalnie)"
                  type="date"
                />
              </div>
              <.field
                field={@form[:owner]}
                label={
                  if @kind == "dinner",
                    do: "Kto gotuje?",
                    else: "Osoba / odpowiedzialny (opcjonalnie)"
                }
                maxlength="80"
              />
              <.field
                field={@form[:body]}
                label={if @kind == "family_note", do: "Wiadomość", else: "Szczegóły (opcjonalnie)"}
                type="textarea"
                maxlength="2000"
              />
              <.field
                :if={@kind in ~w(reminders countdowns)}
                field={@form[:repeat]}
                label="Powtarzanie"
                type="select"
                options={repeat_options(@kind)}
              />
              <.field
                :if={@kind in ~w(reminders family_note)}
                field={@form[:priority]}
                label="Ważność"
                type="select"
                options={[{"Zwykła", 0}, {"Ważna", 1}, {"Najważniejsza", 2}]}
              />
              <button id="family-save" class="primary" phx-disable-with="Zapisywanie…">{if @item.id,
                do: "Zapisz zmiany",
                else: "Dodaj wpis"}</button>
            </div>
          </.form>
        </section>
        <section class="panel family-list-panel">
          <div class="panel-heading">
            <h2>{Family.label(@kind)}</h2><span>Treść niezależna od układu</span>
          </div>
          <p :if={@kind == "today_tomorrow"} class="hint">
            Ekran pokazuje pierwsze 3 niewykonane zadania w kolejności dodania. Po wykonaniu zadania pojawi się kolejne z listy.
          </p>
          <p :if={@empty} id="family-empty" class="muted">
            Jeszcze nic tu nie ma. Dodaj pierwszy wpis — możesz umieścić jego moduł na ekranie w zakładce Układ.
          </p>
          <div id="family-items" phx-update="stream">
            <article
              :for={{dom_id, entry} <- @streams.family_items}
              id={dom_id}
              class="family-row"
              data-kind={entry.kind}
              data-completed={to_string(entry.repeat == "none" and not is_nil(entry.completed_on))}
            >
              <div>
                <strong>{entry.title}</strong><span :if={entry.priority > 0} class="priority">Ważne</span><p class="family-meta">
                  {summary(entry, @today)}<span :if={entry.owner != ""}> · {entry.owner}</span>
                </p><p :if={entry.body != ""} class="family-body">{entry.body}</p>
              </div>
              <div class="row-actions">
                <button
                  :if={
                    entry.kind in ["reminders", "today_tomorrow"] and
                      (entry.repeat != "none" or is_nil(entry.completed_on))
                  }
                  id={"complete-#{entry.id}"}
                  type="button"
                  phx-click="family:complete"
                  phx-value-id={entry.id}
                >Wykonane</button>
                <button
                  :if={entry.kind in ["reminders", "today_tomorrow"] and entry.completed_on}
                  id={"restore-#{entry.id}"}
                  type="button"
                  phx-click="family:restore"
                  phx-value-id={entry.id}
                >Cofnij wykonanie</button>
                <button
                  id={"edit-family-#{entry.id}"}
                  type="button"
                  phx-click="family:edit"
                  phx-value-id={entry.id}
                >Edytuj</button>
                <button
                  id={"delete-family-#{entry.id}"}
                  type="button"
                  phx-click="family:delete"
                  phx-value-id={entry.id}
                  data-confirm="Usunąć ten wpis?"
                  class="danger"
                >Usuń</button>
              </div>
            </article>
          </div>
        </section>
      </div>
    </section>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :options, :list, default: []
  attr :rest, :global, include: ~w(required maxlength)

  def field(assigns) do
    ~H"""
    <label for={@field.id} class="family-field">
      {@label}
      <%= case @type do %>
        <% "textarea" -> %>
          <textarea id={@field.id} name={@field.name} rows="3" {@rest}>{@field.value}</textarea>
        <% "select" -> %>
          <select id={@field.id} name={@field.name} {@rest}><option
            :for={{label, value} <- @options}
            value={value}
            selected={to_string(@field.value) == to_string(value)}
          >
            {label}
          </option></select>
        <% type -> %>
          <input
            id={@field.id}
            name={@field.name}
            type={type}
            value={Phoenix.HTML.Form.normalize_value(type, @field.value)}
            {@rest}
          />
      <% end %>
      <span :for={{message, opts} <- @field.errors} class="error">{error(message, opts)}</span>
    </label>
    """
  end

  defp error(message, opts),
    do:
      Enum.reduce(opts, message, fn {key, value}, text ->
        String.replace(text, "%{#{key}}", to_string(value))
      end)

  defp title_label("today_tomorrow"), do: "Zadanie"
  defp title_label("dinner"), do: "Co jemy?"
  defp title_label("family_note"), do: "Tytuł wiadomości"
  defp title_label(_), do: "Nazwa"
  defp date_label("family_note"), do: "Wyświetlaj od (opcjonalnie)"
  defp date_label("reminders"), do: "Termin / pierwsze wystąpienie"
  defp date_label(_), do: "Data"

  defp repeat_options("reminders"),
    do: [{"Jednorazowo", "none"}, {"Codziennie", "daily"}, {"Co tydzień", "weekly"}]

  defp repeat_options(_), do: [{"Jednorazowo", "none"}, {"Co roku", "yearly"}]

  defp description("today_tomorrow"),
    do:
      "Dodawaj zadania do listy bez wybierania daty. Odhaczaj wykonane zadania, aby pokazać na ekranie kolejne."

  defp description("dinner"), do: "Zaplanuj posiłki na dowolne dni, dodaj osobę gotującą i uwagi."

  defp description("reminders"),
    do:
      "Jednorazowe lub cykliczne obowiązki. Wykonanie cyklicznego zadania odsłania następny termin."

  defp description("countdowns"),
    do: "Urodziny, wakacje, wizyty. Daty coroczne przesuwają się automatycznie."

  defp description("family_note"),
    do:
      "Wiadomości dla wszystkich. Opcjonalne daty ograniczają czas wyświetlania, a ważność ustala kolejność."

  def summary(%{kind: "today_tomorrow"} = item, _today),
    do: if(item.completed_on, do: "Wykonane", else: "Do zrobienia")

  def summary(%{kind: "reminders"} = item, today) do
    case FamilySchedule.due(item, today) do
      :completed ->
        "Wykonane"

      nil ->
        "Bez terminu"

      date ->
        "Termin: #{date}" <>
          if(item.repeat == "none",
            do: "",
            else: " · #{if item.repeat == "daily", do: "codziennie", else: "co tydzień"}"
          )
    end
  end

  def summary(%{kind: "countdowns"} = item, today) do
    date = FamilySchedule.countdown_date(item, today)
    days = Date.diff(date, today)
    "#{date} · " <> if(days < 0, do: "data minęła", else: "#{days} dni")
  end

  def summary(%{kind: "family_note"} = item, today),
    do:
      "#{item.date || "Od teraz"} → #{item.end_date || "bez końca"} · #{if FamilySchedule.active_note?(item, today), do: "aktywna", else: "poza okresem wyświetlania"}"

  def summary(item, _),
    do:
      "#{item.date}" <>
        if(item.time, do: " · #{Calendar.strftime(item.time, "%H:%M")}", else: " · cały dzień")
end
