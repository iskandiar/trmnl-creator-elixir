defmodule TrmnlWeb.DashboardLiveTest do
  use TrmnlWeb.ConnCase
  import Phoenix.LiveViewTest

  test "preschool setup saves free import settings and queues a manual import", %{conn: conn} do
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    view |> element("#add-preschool") |> render_click()
    assert has_element?(view, "#preschool-block-help")
    view |> element("#save") |> render_click()
    [block] = Trmnl.Publication.screen().draft["blocks"]
    assert block["type"] == "preschool"
    view |> element("#open-preschool-settings") |> render_click()
    assert has_element?(view, "#preschool-settings")
    assert has_element?(view, "#preschool-mode option[value='openrouter']")
    refute has_element?(view, "#preschool-mode option[value='gemini']")

    assert has_element?(
             view,
             "#preschool-ai-status a[href='https://openrouter.ai/settings/keys']"
           )

    view
    |> form("#preschool-import-form", menu: %{mode: "plain", enabled: "true"})
    |> render_submit()

    assert Trmnl.PreschoolMenus.status().enabled
    view |> element("#preschool-import") |> render_click()

    assert [%Oban.Job{args: %{"manual" => true}}] =
             Oban.Testing.all_enqueued(worker: Trmnl.PreschoolMenuWorker, repo: Trmnl.Repo)
  end

  test "battery block can be added and saved without calendar or weather settings", %{conn: conn} do
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    view |> element("#add-battery") |> render_click()
    assert has_element?(view, "#battery-settings")
    refute has_element?(view, "#weather-settings")
    refute has_element?(view, "input[name='block[calendars][]']")
    view |> element("#save") |> render_click()
    [block] = Trmnl.Publication.screen().draft["blocks"]
    assert block["type"] == "battery"
    assert block["title"] == "Bateria"
  end

  test "weather location can be configured and persisted without calendar settings", %{conn: conn} do
    conn = init_test_session(conn, admin: TrmnlWeb.Auth.issue())
    {:ok, view, _} = live(conn, "/")
    view |> element("#add-weather") |> render_click()
    assert has_element?(view, "#weather-settings")
    refute has_element?(view, "input[name='block[calendars][]']")

    view
    |> form("form[id^=configure]",
      block: %{title: "Warszawa", latitude: "52.2297", longitude: "21.0122"}
    )
    |> render_submit()

    view |> element("#save") |> render_click()
    [block] = Trmnl.Publication.screen().draft["blocks"]
    assert block["type"] == "weather"
    assert block["latitude"] == "52.2297"
    assert block["longitude"] == "21.0122"

    {:ok, reopened, _} = live(conn, "/")
    reopened |> element(".grid-block") |> render_click()
    assert has_element?(reopened, "#weather-latitude[value='52.2297']")
    assert {:error, _} = Trmnl.Layout.validate(%{"blocks" => [Map.put(block, "latitude", "91")]})
  end

  test "small blocks and 12px text can be configured, saved and reopened", %{conn: conn} do
    conn = init_test_session(conn, admin: TrmnlWeb.Auth.issue())
    {:ok, view, _} = live(conn, "/")
    view |> element("#add-week") |> render_click()

    view
    |> element("form[id^=configure]")
    |> render_submit(%{
      "block" => %{"x" => "0", "y" => "0", "w" => "1", "h" => "1", "font_size" => "12"}
    })

    assert has_element?(view, ".grid-block[data-w='1'][data-h='1']")
    view |> element("#save") |> render_click()
    {:ok, reopened, _} = live(conn, "/")
    assert has_element?(reopened, ".grid-block[data-w='1'][data-h='1']")
    reopened |> element(".grid-block") |> render_click()
    assert has_element?(reopened, "select[name='block[font_size]'] option[value='12'][selected]")
  end

  test "disconnecting an account removes it from settings and calendar choices", %{conn: conn} do
    removed = Trmnl.Fixtures.account()
    retained = Trmnl.Fixtures.account("two@example.com")
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")

    view |> element("#tab-settings") |> render_click()
    assert has_element?(view, "#disconnect-account-#{removed.id}[type=button][data-confirm]")
    view |> element("#disconnect-account-#{removed.id}") |> render_click()
    refute has_element?(view, "#account-#{removed.id}")
    assert has_element?(view, "#account-#{retained.id}")

    view |> element("#tab-layout") |> render_click()
    view |> element("#add-agenda") |> render_click()
    refute has_element?(view, "input[name='block[calendars][]'][value='#{removed.id}:primary']")
    assert has_element?(view, "input[name='block[calendars][]'][value='#{retained.id}:primary']")

    view |> element("#tab-settings") |> render_click()
    view |> element("#disconnect-account-#{retained.id}") |> render_click()
    refute has_element?(view, "#account-#{retained.id}")
    assert Trmnl.Calendars.accounts() == []
  end

  test "dashboard requires auth; password login creates a session", %{conn: conn} do
    assert conn |> get("/") |> redirected_to() == "/login"
    assert conn |> post("/login", password: "wrong") |> response(401)
    logged = post(conn, "/login", password: "test-password")
    assert redirected_to(logged) == "/"
    assert TrmnlWeb.Auth.valid?(get_session(logged, :admin))
  end

  test "add, configure, reject overlap, save, reopen and remove", %{conn: conn} do
    conn = init_test_session(conn, admin: TrmnlWeb.Auth.issue())
    {:ok, view, _} = live(conn, "/")
    view |> element("#add-agenda") |> render_click()
    assert has_element?(view, ".grid-block")

    view
    |> element("form[id^=configure]")
    |> render_submit(%{
      "block" => %{
        "title" => "Rodzina",
        "text" => "",
        "x" => "10",
        "y" => "0",
        "w" => "10",
        "h" => "6",
        "font_size" => "18",
        "days" => "7"
      }
    })

    assert render(view) =~ "Rodzina"
    view |> element("#save") |> render_click()
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Rodzina"
    view |> element(".grid-block") |> render_click()
    view |> element("#remove-block") |> render_click()
    refute has_element?(view, ".grid-block")
  end

  test "invalid OAuth state never exchanges credentials", %{conn: conn} do
    conn =
      init_test_session(conn,
        admin: TrmnlWeb.Auth.issue(),
        oauth_state: {"right", System.system_time(:second)}
      )

    assert get(conn, "/oauth/callback?state=wrong&code=secret") |> response(400)
    assert Trmnl.Calendars.accounts() == []
  end

  test "OAuth state is single-use and two accounts can connect", %{conn: conn} do
    conn =
      init_test_session(conn,
        admin: TrmnlWeb.Auth.issue(),
        oauth_state: {"first", System.system_time(:second)}
      )

    conn = get(conn, "/oauth/callback?state=first&code=one@example.com")
    assert redirected_to(conn) == "/"
    assert get_session(conn, :oauth_state) == nil

    conn =
      conn |> recycle() |> init_test_session(oauth_state: {"second", System.system_time(:second)})

    conn = get(conn, "/oauth/callback?state=second&code=two@example.com")
    assert redirected_to(conn) == "/"
    assert length(Trmnl.Calendars.accounts()) == 2
  end

  test "missing OAuth credentials stay on dashboard with setup guidance", %{conn: conn} do
    old_id = Application.get_env(:trmnl, :google_client_id)
    old_secret = Application.get_env(:trmnl, :google_client_secret)

    on_exit(fn ->
      Application.put_env(:trmnl, :google_client_id, old_id)
      Application.put_env(:trmnl, :google_client_secret, old_secret)
    end)

    for key <- [:google_client_id, :google_client_secret],
        do: Application.put_env(:trmnl, key, "")

    conn = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> get("/oauth/start")
    assert redirected_to(conn) == "/"
    assert get_session(conn, :oauth_state) == nil
    {:ok, _view, html} = conn |> recycle() |> live("/")
    assert html =~ "Skonfiguruj Google OAuth"
  end

  test "slow preview does not block editing", %{conn: conn} do
    Application.put_env(:trmnl, :renderer, Trmnl.BlockedRenderer)
    Application.put_env(:trmnl, :render_observer, self())

    on_exit(fn ->
      Application.put_env(:trmnl, :renderer, Trmnl.FakeRenderer)
      Application.delete_env(:trmnl, :render_observer)
    end)

    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    task = Task.async(fn -> view |> element("#preview") |> render_click() end)
    assert_receive {:render_started, renderer}, 2000
    result = Task.yield(task, 500)
    send(renderer, :continue)
    if result == nil, do: Task.await(task)

    assert match?({:ok, _}, result),
           "Preview blocked the LiveView process until rendering completed"

    view |> element("#add-text") |> render_click()
    assert has_element?(view, ".grid-block")
    render_async(view)
    assert has_element?(view, "#preview-image")
  end

  test "publishing runs in background and does not publish later working edits", %{conn: conn} do
    Application.put_env(:trmnl, :renderer, Trmnl.BlockedRenderer)
    Application.put_env(:trmnl, :render_observer, self())

    on_exit(fn ->
      Application.put_env(:trmnl, :renderer, Trmnl.FakeRenderer)
      Application.delete_env(:trmnl, :render_observer)
    end)

    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    view |> element("#add-header") |> render_click()
    view |> element("#publish") |> render_click()
    assert_receive {:render_started, renderer}, 2000
    assert has_element?(view, "#publish[disabled]")
    view |> element("#add-text") |> render_click()
    assert has_element?(view, ".grid-block[data-y=\"0\"]")
    send(renderer, :continue)
    render_async(view)
    assert length(Trmnl.Publication.screen().draft["blocks"]) == 1
    assert length(Trmnl.Publication.screen().published["blocks"]) == 1
    assert render(view) =~ "Niezapisane zmiany"
    refute has_element?(view, "#publish[disabled]")
  end

  test "failed asynchronous preview can be retried", %{conn: conn} do
    Application.put_env(:trmnl, :fail_render, true)
    on_exit(fn -> Application.delete_env(:trmnl, :fail_render) end)
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    view |> element("#preview") |> render_click()
    assert render_async(view) =~ "Podgląd nie powiódł się"
    refute has_element?(view, "#preview[disabled]")
    Application.delete_env(:trmnl, :fail_render)
    view |> element("#preview") |> render_click()
    render_async(view)
    assert has_element?(view, "#preview-image")
  end
end
