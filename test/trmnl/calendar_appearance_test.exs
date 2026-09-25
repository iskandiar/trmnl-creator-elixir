defmodule Trmnl.CalendarAppearanceTest do
  use Trmnl.DataCase
  import Trmnl.Fixtures
  alias Trmnl.{Layout, Publication, ScreenHTML}

  test "clock uses Warsaw time across DST and poll interval follows publication only" do
    layout = %{"blocks" => [block(%{"type" => "header"})]}
    html = ScreenHTML.render(layout, [], ~U[2026-03-29 01:30:00Z])
    assert html =~ "03:30"
    assert html =~ "29.03.2026"
    assert html =~ "±5 min"
    assert Layout.poll_seconds(nil) == 900
    {:ok, saved} = Publication.save(layout, 0)
    assert Layout.poll_seconds(saved.published) == 900
    {:ok, published} = Publication.publish()
    assert Layout.poll_seconds(published.published) == 240
    {:ok, _} = Publication.save(%{"blocks" => []}, 1)
    assert :ok = Trmnl.ClockWorker.perform(%{})
    assert Publication.screen().published == layout
    assert Publication.screen().draft == %{"blocks" => []}
  end

  test "all appearances and calendar variants validate, persist and render" do
    for appearance <- ~w(classic minimal contrast),
        {kind, style} <- [{"agenda", "grouped"}, {"week", "rows"}, {"month", "list"}] do
      layout = %{
        "blocks" => [
          block(%{
            "type" => kind,
            "w" => 20,
            "h" => 10,
            "appearance" => appearance,
            "density" => "compact",
            "calendar_style" => style
          })
        ]
      }

      assert {:ok, ^layout} = Layout.validate(layout)
      html = ScreenHTML.render(layout, [event()], ~U[2026-03-29 01:30:00Z])
      assert html =~ "#{appearance} compact"

      if kind == "month" do
        assert html =~ "Marzec 2026"
        assert html =~ "month-day is-today"
        assert html =~ "poza zakresem synchronizacji"
      end

      if kind == "week", do: assert(html =~ "week-rows")
    end

    assert {:error, _} = Layout.validate(%{"blocks" => [block(%{"appearance" => "<script>"})]})
    assert {:error, _} = Layout.validate(%{"blocks" => [block(%{"type" => "month", "h" => 2})]})
  end
end
