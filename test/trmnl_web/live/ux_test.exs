defmodule TrmnlWeb.UXTest do
  use TrmnlWeb.ConnCase
  import Phoenix.LiveViewTest

  test "appearance controls and direct content editing preserve layout", %{conn: conn} do
    {:ok, view, _} = conn |> init_test_session(admin: TrmnlWeb.Auth.issue()) |> live("/")
    view |> element("#add-dinner") |> render_click()

    view
    |> form("form[id^=configure-]", block: %{appearance: "contrast", density: "comfortable"})
    |> render_submit()

    assert has_element?(view, "#block-appearance option[value=contrast][selected]")
    view |> element("#edit-block-content") |> render_click()
    assert has_element?(view, "#module-dinner[aria-pressed=true]")
    assert has_element?(view, "#pane-layout[hidden]")
    view |> element("#tab-layout") |> render_click()
    assert has_element?(view, "#block-appearance option[value=contrast][selected]")
  end

  test "failed login retains a usable form and accessible error", %{conn: conn} do
    response = conn |> post("/login", %{password: "wrong"}) |> html_response(401)
    assert response =~ "role=alert"
    assert response =~ "id=\"login-form\""
    assert response =~ "autocomplete=\"current-password\""
    refute response =~ "value=\"wrong\""
  end
end
