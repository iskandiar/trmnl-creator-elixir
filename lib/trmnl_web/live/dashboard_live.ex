defmodule TrmnlWeb.DashboardLive do
  use TrmnlWeb, :live_view
  alias Trmnl.{Publication, Layout, Calendars, Devices, Diagnostics, Family}
  alias TrmnlWeb.{FamilyEditor, FamilyContent}
  @impl true
  def mount(_, _, socket) do
    s = Publication.screen()
    if connected?(socket), do: Process.send_after(self(), :status, 5000)

    {:ok,
     socket
     |> assign(
       tab: "layout",
       draft_layout: Layout.upgrade(s.draft),
       revision: s.revision,
       selected: nil,
       preview: nil,
       preview_layout: nil,
       dirty: false,
       notice: nil,
       rendering: nil,
       google_configured: Trmnl.Google.configured?(),
       google_callback: Application.fetch_env!(:trmnl, :google_redirect_uri)
     )
     |> status()
     |> FamilyEditor.init()}
  end

  defp status(socket),
    do:
      assign(socket,
        accounts: Calendars.accounts(),
        calendars: Calendars.options(),
        device: Devices.device(),
        diagnostics: Diagnostics.recent(),
        published_at: Publication.screen().published_at
      )

  @impl true
  def handle_info(:status, socket) do
    Process.send_after(self(), :status, 5000)
    {:noreply, status(socket)}
  end

  def handle_info(:family_changed, socket), do: {:noreply, FamilyEditor.refresh(socket)}

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(content layout settings),
    do: {:noreply, assign(socket, tab: tab)}

  def handle_event("family:" <> event, params, socket),
    do: FamilyEditor.handle_event(event, params, socket)

  def handle_event("edit-content", %{"kind" => kind}, socket)
      when kind in ~w(today_tomorrow dinner reminders countdowns family_note) do
    FamilyEditor.handle_event("module", %{"kind" => kind}, assign(socket, tab: "content"))
  end

  def handle_event("add", %{"type" => type}, socket)
      when type in ~w(header text agenda week month today_tomorrow dinner reminders countdowns family_note) do
    {w, h} =
      case type do
        "week" -> {20, 4}
        "month" -> {10, 6}
        "agenda" -> {8, 4}
        "today_tomorrow" -> {8, 3}
        kind when kind in ~w(dinner reminders countdowns family_note) -> {6, 3}
        "header" -> {8, 2}
        _ -> {6, 2}
      end

    candidate =
      for y <- 0..11, x <- 0..19 do
        %{
          "id" => Ecto.UUID.generate(),
          "type" => type,
          "x" => x,
          "y" => y,
          "w" => w,
          "h" => h,
          "title" =>
            %{
              "header" => "Dzisiaj",
              "text" => "Notatka",
              "agenda" => "Plan dnia",
              "week" => "Najbliższe 7 dni",
              "month" => "Miesiąc",
              "today_tomorrow" => "Lista zadań",
              "dinner" => "Plan posiłków",
              "reminders" => "Obowiązki domowe",
              "countdowns" => "Odliczanie",
              "family_note" => "Dla rodziny"
            }[type],
          "text" => "",
          "calendars" => Enum.map(socket.assigns.calendars, &elem(&1, 0)),
          "font_size" => 14,
          "days" => 7
        }
      end

    block =
      Enum.find(candidate, fn b ->
        match?(
          {:ok, _},
          Layout.validate(%{"blocks" => socket.assigns.draft_layout["blocks"] ++ [b]})
        )
      end)

    if block do
      {:noreply,
       assign(socket,
         draft_layout: %{"blocks" => socket.assigns.draft_layout["blocks"] ++ [block]},
         selected: block["id"],
         dirty: true,
         notice: nil
       )}
    else
      {:noreply, assign(socket, notice: "Brak miejsca. Zmniejsz lub usuń inny blok.")}
    end
  end

  def handle_event("select", %{"id" => id}, socket), do: {:noreply, assign(socket, selected: id)}

  def handle_event("remove", _, socket) do
    blocks =
      Enum.reject(socket.assigns.draft_layout["blocks"], &(&1["id"] == socket.assigns.selected))

    {:noreply, assign(socket, draft_layout: %{"blocks" => blocks}, selected: nil, dirty: true)}
  end

  def handle_event("configure", %{"block" => attrs}, socket) do
    updates =
      Map.take(attrs, ~w(title text calendars appearance density calendar_style))
      |> Map.put_new("calendars", [])

    updates =
      Enum.reduce(~w(x y w h font_size days), updates, fn k, acc ->
        if Map.has_key?(attrs, k), do: Map.put(acc, k, parse(attrs[k])), else: acc
      end)

    update_block(socket, socket.assigns.selected, updates)
  end

  def handle_event("geometry", attrs, socket) do
    {:noreply, socket} = update_block(socket, attrs["id"], Map.take(attrs, ~w(x y w h)))
    block = Enum.find(socket.assigns.draft_layout["blocks"], &(&1["id"] == attrs["id"]))

    {:reply, %{geometry: block && Map.take(block, ~w(x y w h))},
     assign(socket, selected: attrs["id"])}
  end

  def handle_event("save", _, %{assigns: %{rendering: :publish}} = socket), do: {:noreply, socket}

  def handle_event("save", _, socket) do
    {:noreply, save(socket)}
  end

  def handle_event(action, _, %{assigns: %{rendering: rendering}} = socket)
      when action in ["preview", "publish"] and rendering != nil, do: {:noreply, socket}

  def handle_event("preview", _, socket) do
    layout = socket.assigns.draft_layout

    {:noreply,
     socket
     |> assign(
       preview_layout: layout,
       rendering: :preview,
       notice: "Renderowanie podglądu… Możesz dalej edytować ekran."
     )
     |> start_async(:preview, fn -> Publication.preview(layout) end)}
  end

  def handle_event("publish", _, socket) do
    socket = save(socket)

    if socket.assigns.dirty do
      {:noreply, socket}
    else
      revision = socket.assigns.revision

      {:noreply,
       socket
       |> assign(rendering: :publish, notice: "Publikowanie zapisanego szkicu…")
       |> start_async(:publish, fn -> Publication.publish(revision) end)}
    end
  end

  def handle_event("calendars", %{"account" => id} = params, socket) do
    case Calendars.select(id, Map.get(params, "selected", [])) do
      {:ok, _} ->
        %{} |> Trmnl.SyncWorker.new() |> Oban.insert()

        {:noreply,
         socket |> assign(notice: "Zapisano kalendarze. Synchronizacja w kolejce.") |> status()}

      {:error, _} ->
        {:noreply, assign(socket, notice: "Nieprawidłowy wybór kalendarzy.")}
    end
  end

  def handle_event("disconnect-account", %{"account" => id}, socket) do
    case Calendars.disconnect(id) do
      {:ok, :ok} ->
        {:noreply,
         socket
         |> assign(
           notice: "Odłączono konto. Odświeżenie ekranu w kolejce.",
           preview: nil,
           preview_layout: nil
         )
         |> status()}

      {:error, _} ->
        {:noreply, assign(socket, notice: "Nie udało się odłączyć konta. Spróbuj ponownie.")}
    end
  end

  def handle_event("sync", _, socket) do
    %{} |> Trmnl.SyncWorker.new() |> Oban.insert()

    {:noreply,
     assign(socket, notice: "Synchronizacja w kolejce. Status odświeża się co 5 sekund.")}
  end

  def handle_event("pair", %{"mac" => mac}, socket) do
    case Devices.allow_pairing(mac) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(notice: "Parowanie otwarte na 10 minut dla wskazanego adresu MAC.")
         |> status()}

      {:error, message} ->
        {:noreply, assign(socket, notice: message)}
    end
  end

  @impl true
  def handle_async(:preview, {:ok, {:ok, image}}, socket) do
    {:noreply,
     assign(socket,
       rendering: nil,
       preview: "data:image/png;base64," <> Base.encode64(image),
       notice: "Podgląd gotowy. Pokazuje układ z chwili rozpoczęcia renderowania."
     )}
  end

  def handle_async(:preview, _, socket) do
    {:noreply,
     assign(socket,
       rendering: nil,
       notice: "Podgląd nie powiódł się. Sprawdź usługę renderer i spróbuj ponownie."
     )}
  end

  def handle_async(:publish, {:ok, {:ok, _}}, socket) do
    {:noreply,
     socket
     |> assign(
       rendering: nil,
       notice: "Opublikowano zapisany szkic. Późniejsze zmiany pozostają w edytorze."
     )
     |> status()}
  end

  def handle_async(:publish, {:ok, {:error, message}}, socket) do
    {:noreply, socket |> assign(rendering: nil, notice: message) |> status()}
  end

  def handle_async(:publish, {:exit, _}, socket) do
    {:noreply,
     socket
     |> assign(
       rendering: nil,
       notice: "Publikacja nie powiodła się. Sprawdź diagnostykę i spróbuj ponownie."
     )
     |> status()}
  end

  defp save(socket) do
    case Publication.save(socket.assigns.draft_layout, socket.assigns.revision) do
      {:ok, s} -> assign(socket, revision: s.revision, dirty: false, notice: "Zapisano szkic.")
      {:error, message} -> assign(socket, notice: message, dirty: true)
    end
  end

  defp update_block(socket, id, updates) do
    blocks =
      Enum.map(socket.assigns.draft_layout["blocks"], fn b ->
        if b["id"] == id, do: Map.merge(b, updates), else: b
      end)

    case Layout.validate(%{"blocks" => blocks}) do
      {:ok, layout} -> {:noreply, assign(socket, draft_layout: layout, dirty: true, notice: nil)}
      {:error, message} -> {:noreply, assign(socket, notice: message)}
    end
  end

  defp parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse(_), do: nil

  defp selected(assigns),
    do: Enum.find(assigns.draft_layout["blocks"], &(&1["id"] == assigns.selected))

  defp block_label(type),
    do:
      Family.label(type) ||
        %{
          "header" => "Data i godzina",
          "agenda" => "Agenda",
          "week" => "Tydzień",
          "month" => "Miesiąc",
          "text" => "Tekst"
        }[type]

  defp format_time(nil), do: "Brak"

  defp format_time(dt),
    do: dt |> DateTime.shift_zone!("Europe/Warsaw") |> Calendar.strftime("%d.%m.%Y %H:%M")

  @impl true
  def render(assigns) do
    block = selected(assigns)

    assigns =
      assign(assigns,
        block: block,
        block_form: to_form(block || %{}, as: :block),
        pair_form: to_form(%{"mac" => ""})
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <header class="topbar">
        <a href="/" class="brand">TRMNL <span>Calendar Studio</span></a><.link
          href="/logout"
          method="delete"
        >Wyloguj</.link>
      </header>
      <main>
        <div class="intro">
          <div>
            <p class="eyebrow">TWÓJ EKRAN / 800 × 480</p><h1>Miejsce na Twój dzień.</h1><p>
              Kalendarze, plany i małe przypomnienia. Ułóż je po swojemu.
            </p>
          </div><div class="status">
            <span class="dot"></span> {if @published_at,
              do: "Obraz odświeżono #{format_time(@published_at)}",
              else: "Czeka na pierwszą publikację"}
          </div>
        </div>
        <div :if={@notice} id="notice" role="status" class="notice">{@notice}</div>
        <nav class="dashboard-tabs" role="tablist" aria-label="Zarządzanie ekranem">
          <button
            :for={
              {key, label} <- [
                {"content", "Treść rodzinna"},
                {"layout", "Układ ekranu"},
                {"settings", "Kalendarze i urządzenie"}
              ]
            }
            id={"tab-#{key}"}
            role="tab"
            type="button"
            aria-selected={to_string(@tab == key)}
            aria-controls={"pane-#{key}"}
            phx-click="tab"
            phx-value-tab={key}
            class={[@tab == key && "active"]}
          >{label}</button>
        </nav>
        <section
          id="pane-content"
          role="tabpanel"
          aria-labelledby="tab-content"
          hidden={@tab != "content"}
        >
          <FamilyContent.panel
            kind={@family_kind}
            item={@family_item}
            form={@family_form}
            form_epoch={@family_form_epoch}
            streams={@streams}
            empty={@family_empty}
            notice={@family_notice}
            today={@family_today}
          />
        </section>
        <section
          id="pane-layout"
          role="tabpanel"
          aria-labelledby="tab-layout"
          hidden={@tab != "layout"}
        >
          <div class="workspace">
            <section class="editor-panel">
              <div class="panel-heading">
                <h2>Edytor ekranu</h2><span>{if @dirty,
                  do: "Niezapisane zmiany",
                  else: "Szkic zapisany"} · siatka 20 × 12</span>
              </div>
              <div class="toolbar">
                <span>Dodaj blok</span><button
                  :for={
                    {type, label} <-
                      [
                        {"header", "Data i godzina"},
                        {"agenda", "Agenda"},
                        {"week", "Tydzień"},
                        {"month", "Miesiąc"},
                        {"text", "Tekst (statyczny)"}
                      ] ++ Family.labels()
                  }
                  phx-click="add"
                  phx-value-type={type}
                  id={"add-#{type}"}
                >+ {label}</button>
              </div>
              <div class="canvas-scroll">
                <div id="canvas" phx-hook="Grid" class="canvas">
                  <div :if={@draft_layout["blocks"] == []} class="empty">
                    <strong>Tu zaczyna się Twój dzień.</strong><p>
                      Dodaj pierwszy blok z paska powyżej.
                    </p>
                  </div>
                  <div
                    :for={b <- @draft_layout["blocks"]}
                    id={"block-#{b["id"]}"}
                    data-block={b["id"]}
                    data-x={b["x"]}
                    data-y={b["y"]}
                    data-w={b["w"]}
                    data-h={b["h"]}
                    tabindex="0"
                    role="button"
                    aria-label={"#{block_label(b["type"])}: #{b["title"]}. Enter — ustawienia."}
                    class={["grid-block", @selected == b["id"] && "selected"]}
                    style={"left:#{b["x"]*40}px;top:#{b["y"]*40}px;width:#{b["w"]*40}px;height:#{b["h"]*40}px"}
                    phx-click="select"
                    phx-value-id={b["id"]}
                  >
                    <span class="block-type">{block_label(b["type"])}</span><strong>{b["title"]}</strong><p>
                      {if b["type"] == "text",
                        do: b["text"],
                        else:
                          if(b["type"] in Family.kinds(),
                            do: "Treść z panelu rodzinnego",
                            else: "#{b["w"]} × #{b["h"]} · #{length(b["calendars"])} kalendarzy"
                          )}
                    </p><span class="resize" aria-label="Zmień rozmiar">↘</span>
                  </div>
                </div>
              </div>
              <div class="actions">
                <button id="save" phx-click="save" disabled={@rendering == :publish}>Zapisz szkic</button><button
                  id="preview"
                  disabled={@rendering != nil}
                  phx-click="preview"
                  phx-disable-with="Renderowanie…"
                >Podgląd</button><button
                  class="primary"
                  id="publish"
                  disabled={@rendering != nil}
                  phx-click="publish"
                  phx-disable-with="Publikowanie…"
                >Publikuj na TRMNL ↗</button>
              </div>
              <p class="hint">
                Przeciągnij blok, aby go przesunąć. Użyj prawego dolnego rogu, aby zmienić rozmiar. Podgląd i publikacja używają tego samego renderera.
              </p>
            </section>
            <aside class="inspector">
              <h2>Ustawienia bloku</h2>
              <p :if={!@block} class="muted">
                Wybierz blok na ekranie, aby zmienić jego zawartość i położenie.
              </p>
              <.form
                :if={@block}
                for={@block_form}
                id={"configure-#{@block["id"]}"}
                phx-submit="configure"
              >
                <label>Tytuł<input
                  name="block[title]"
                  value={@block_form[:title].value}
                  maxlength="100"
                /></label>
                <div class="geometry">
                  <label :for={key <- ~w(x y w h)}>{%{
                    "x" => "Kolumna",
                    "y" => "Wiersz",
                    "w" => "Szerokość",
                    "h" => "Wysokość"
                  }[key]}<input
                    aria-label={key}
                    min={if key in ~w(w h), do: 1, else: 0}
                    max={if key in ~w(x w), do: 20, else: 12}
                    type="number"
                    name={"block[#{key}]"}
                    value={@block_form[key].value}
                    required
                  /></label>
                </div>
                <label>Wygląd<select id="block-appearance" name="block[appearance]"><option
                  :for={
                    {value, label} <- [
                      {"classic", "Klasyczny"},
                      {"minimal", "Minimalny"},
                      {"contrast", "Kontrastowy nagłówek"}
                    ]
                  }
                  value={value}
                  selected={Map.get(@block, "appearance", "classic") == value}
                >
                  {label}
                </option></select></label>
                <label>Odstępy<select id="block-density" name="block[density]"><option
                  :for={{value, label} <- [{"compact", "Zwarte"}, {"comfortable", "Swobodne"}]}
                  value={value}
                  selected={Map.get(@block, "density", "compact") == value}
                >
                  {label}
                </option></select></label>
                <label :if={@block["type"] in ~w(agenda week)}>Układ kalendarza<select
                  id="calendar-style"
                  name="block[calendar_style]"
                ><option
                  :for={
                    {value, label} <-
                      if(@block["type"] == "agenda",
                        do: [{"list", "Lista wydarzeń"}, {"grouped", "Grupowanie dni"}],
                        else: [{"list", "7 kolumn"}, {"rows", "Dni w wierszach"}]
                      )
                  }
                  value={value}
                  selected={Map.get(@block, "calendar_style", "list") == value}
                >
                  {label}
                </option></select></label>
                <p :if={@block["type"] == "header"} class="hint">
                  Czas z momentu generowania obrazu · ±5 min przy działającym połączeniu. TRMNL pobiera ekran z zegarem co 4 minuty.
                </p>
                <label>Rozmiar tekstu<select name="block[font_size]"><option
                  :for={n <- [12, 14, 16, 18, 20, 24]}
                  value={n}
                  selected={@block["font_size"] == n}
                >
                  {n} px
                </option></select></label>
                <label :if={@block["type"] in ~w(agenda dinner reminders)}>Liczba dni<input
                  name="block[days]"
                  type="number"
                  min="1"
                  max="30"
                  value={@block_form[:days].value}
                /></label>
                <label :if={@block["type"] == "text"}>Tekst<textarea
                  name="block[text]"
                  rows="4"
                  maxlength="2000"
                >{@block_form[:text].value}</textarea></label>
                <p :if={@block["type"] in Family.kinds()} class="notice">
                  Treścią tego modułu zarządzasz w zakładce <button
                    type="button"
                    phx-click="edit-content"
                    phx-value-kind={@block["type"]}
                    id="edit-block-content"
                  >Edytuj treść</button>. Zmiany treści działają niezależnie od szkicu układu.
                </p>
                <fieldset :if={@block["type"] in ~w(agenda week month)}>
                  <legend>Kalendarze tego bloku</legend><label
                    :for={{key, label} <- @calendars}
                    class="check"
                  ><input
                    type="checkbox"
                    name="block[calendars][]"
                    value={key}
                    checked={key in @block["calendars"]}
                  />{label}</label><p :if={@calendars == []} class="muted">
                    Połącz konto i wybierz kalendarze w zakładce „Kalendarze i urządzenie”.
                  </p>
                </fieldset>
                <button id="apply-block">Zastosuj</button><button
                  type="button"
                  class="danger"
                  phx-click="remove"
                  id="remove-block"
                >Usuń blok</button>
              </.form>
            </aside>
          </div>
          <section :if={@preview} class="panel preview">
            <p :if={@preview_layout != @draft_layout} id="preview-stale" class="notice">
              Układ zmienił się od wygenerowania tego podglądu. Kliknij „Podgląd”, aby go odświeżyć.
            </p>
            <p class="hint">
              Obraz z chwili generowania. Po zmianie rodzinnej treści lub kalendarzy odśwież podgląd.
            </p>
            <h2>Podgląd urządzenia</h2><img
              id="preview-image"
              src={@preview}
              width="800"
              height="480"
              alt="Monochromatyczny podgląd ekranu TRMNL"
            />
          </section>
        </section>
        <section
          id="pane-settings"
          role="tabpanel"
          aria-labelledby="tab-settings"
          hidden={@tab != "settings"}
        >
          <div class="lower-grid">
            <section class="panel">
              <div class="panel-heading">
                <h2>Połączone kalendarze</h2><a
                  href={if @google_configured, do: "/oauth/start", else: "#google-setup"}
                  class="button"
                >{if @google_configured, do: "+ Konto Google", else: "Skonfiguruj Google"}</a>
              </div><p class="muted">Tylko odczyt · Europe/Warsaw · odświeżanie co 5 minut</p>
              <div :if={!@google_configured} id="google-setup" class="notice">
                <h3>Skonfiguruj Google OAuth</h3>
                <p>
                  Brakuje danych klienta Google. Utwórz klienta typu „Aplikacja internetowa” w <a
                    href="https://console.cloud.google.com/auth/clients"
                    target="_blank"
                    rel="noopener noreferrer"
                  >Google Cloud</a>, włącz Calendar API i dodaj swoje konto jako użytkownika testowego.
                </p>
                <p>Autoryzowany adres przekierowania: <code>{@google_callback}</code></p>
                <p>
                  Pobierz plik JSON klienta, uzupełnij konfigurację serwera i uruchom go ponownie. Dopiero wtedy będzie można połączyć konto.
                </p>
              </div>
              <p :if={@accounts == [] and @google_configured}>
                Połącz pierwsze konto, aby zobaczyć wydarzenia.
              </p>
              <form
                :for={a <- @accounts}
                id={"account-#{a.id}"}
                phx-submit="calendars"
                class="account"
              >
                <strong>{a.label}</strong><input type="hidden" name="account" value={a.id} /><label
                  :for={c <- a.calendars}
                  class="check"
                ><input
                  type="checkbox"
                  name="selected[]"
                  value={c["id"]}
                  checked={c["id"] in a.selected}
                />{c[
                  "summary"
                ]}</label><p>Ostatnia synchronizacja: {format_time(a.synced_at)}</p><p
                  :if={a.error}
                  class="error"
                >
                  {a.error}
                </p><button>Zapisz kalendarze</button>
                <button
                  id={"disconnect-account-#{a.id}"}
                  type="button"
                  class="danger"
                  phx-click="disconnect-account"
                  phx-value-account={a.id}
                  data-confirm={"Odłączyć konto #{a.label}? Kalendarze i wydarzenia w Google pozostaną bez zmian."}
                >Odłącz konto</button>
              </form>
              <button id="sync" phx-click="sync">Synchronizuj teraz / ponów</button>
            </section>
            <section class="panel">
              <h2>Twoje urządzenie</h2><p>
                TRMNL OG · 800 × 480 · co 4 min z zegarem / co 15 min bez zegara
              </p><.form
                for={@pair_form}
                id="pair-form"
                phx-submit="pair"
              >
                <label>Adres MAC<input
                  name={@pair_form[:mac].name}
                  value={@pair_form[:mac].value}
                  placeholder="AA:BB:CC:DD:EE:FF"
                  required
                /></label><button>Otwórz parowanie / sparuj ponownie</button>
              </.form>
              <dl :if={@device}>
                <dt>MAC</dt><dd>{@device.mac}</dd><dt>Ostatni kontakt</dt><dd>
                  {format_time(@device.last_contact)}
                </dd><dt>Bateria / Wi-Fi</dt><dd>
                  {@device.battery || "—"} V / {@device.rssi || "—"} dBm
                </dd><dt>Parowanie do</dt><dd>{format_time(@device.pair_until)}</dd>
              </dl>
            </section>
          </div>
          <section class="panel diagnostics">
            <h2>Diagnostyka</h2><p :if={@diagnostics == []}>Brak zarejestrowanych błędów.</p><article :for={
              d <- @diagnostics
            }>
              <time>{format_time(d.inserted_at)}</time><strong>{d.kind}</strong><span>{d.message}</span>
            </article>
          </section>
        </section>
        <footer>
          TRMNL / CALENDAR STUDIO <span>Polski · Europe/Warsaw · Poniedziałek → Niedziela</span>
        </footer>
      </main>
    </Layouts.app>
    """
  end
end
