defmodule TrmnlWeb.FamilyContentTest do
  use TrmnlWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Trmnl.{Family, Publication}

  setup %{conn: conn} do
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    %{view: view}
  end

  test "todos support complete and undo without dates, time or calendar settings", %{view: view} do
    view |> element("#tab-content") |> render_click()

    for n <- 1..3 do
      view
      |> form("#family-form", family: %{title: "Task #{n}"})
      |> render_submit()
    end

    refute has_element?(view, "[name='family[time]']")
    refute has_element?(view, "[name='family[date]']")

    view
    |> form("#family-form", family: %{title: "Fourth"})
    |> render_submit()

    refute has_element?(view, "#family-form .error")
    assert length(Family.list("today_tomorrow")) == 4
    [item | _] = Family.list("today_tomorrow")
    view |> element("#complete-#{item.id}") |> render_click()
    assert has_element?(view, "#restore-#{item.id}")
    view |> element("#restore-#{item.id}") |> render_click()
    assert has_element?(view, "#complete-#{item.id}")
    view |> element("#tab-layout") |> render_click()
    view |> element("#add-today_tomorrow") |> render_click()
    refute has_element?(view, "[name='block[calendars][]']")
  end

  test "tabs preserve working layout; every module has independent CRUD", %{
    view: view,
    conn: conn
  } do
    initial = Publication.screen()
    view |> element("#add-header") |> render_click()
    view |> element("#tab-content") |> render_click()
    assert has_element?(view, "#pane-layout[hidden]")

    for kind <- Family.kinds() do
      view |> element("#module-#{kind}") |> render_click()
      attrs = %{title: "Wpis #{kind}", body: "Szczegóły", date: "2026-09-24", owner: "Tata"}
      attrs = if kind == "today_tomorrow", do: Map.delete(attrs, :date), else: attrs
      view |> form("#family-form", family: attrs) |> render_submit()
      [item] = Family.list(kind)
      assert has_element?(view, "#family_items-#{item.id}")
      view |> element("#edit-family-#{item.id}") |> render_click()
      view |> form("#family-form", family: %{title: "Zmienione"}) |> render_submit()
      assert Family.get(item.id).title == "Zmienione"
    end

    assert Publication.screen().draft == initial.draft
    assert Publication.screen().revision == initial.revision
    view |> element("#tab-layout") |> render_click()
    assert has_element?(view, ".grid-block[data-block]")
    assert has_element?(view, "#pane-content[hidden]")
    # Content survives reconnect without saving a layout.
    {:ok, reopened, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    reopened |> element("#tab-content") |> render_click()
    assert has_element?(reopened, "#family-items article")
    [note] = Family.list("family_note")
    view |> element("#tab-content") |> render_click()
    view |> element("#module-family_note") |> render_click()
    view |> element("#delete-family-#{note.id}") |> render_click()
    refute has_element?(view, "#family_items-#{note.id}")
  end

  test "reminders complete/restore and validation stays in the form", %{view: view} do
    view |> element("#tab-content") |> render_click()
    view |> element("#module-reminders") |> render_click()
    view |> form("#family-form", family: %{title: "Śmieci", repeat: "weekly"}) |> render_submit()
    assert has_element?(view, "#family-form .error")
    assert Family.list("reminders") == []
    view |> form("#family-form", family: %{title: "Śmieci", repeat: "none"}) |> render_submit()
    [item] = Family.list("reminders")
    view |> element("#complete-#{item.id}") |> render_click()
    assert has_element?(view, "#restore-#{item.id}")
    assert Family.get(item.id).completed_on
    view |> element("#restore-#{item.id}") |> render_click()
    assert has_element?(view, "#complete-#{item.id}")
    assert Family.get(item.id).completed_on == nil
  end

  test "all family block types can be placed and have no embedded content text field", %{
    view: view
  } do
    for kind <- Family.kinds() do
      view |> element("#add-#{kind}") |> render_click()
      assert has_element?(view, "#apply-block")
      refute has_element?(view, "textarea[name='block[text]']")
      view |> element("#remove-block") |> render_click()
    end
  end
end
