defmodule Trmnl.LayoutTest do
  use ExUnit.Case, async: true
  import Trmnl.Fixtures

  test "bounds, overlaps, duplicate ids, zero sizes and malformed inputs are rejected" do
    assert {:ok, _} =
             Trmnl.Layout.validate(%{"blocks" => [block(), block(%{"id" => "two", "x" => 10})]})

    for b <- [
          block(%{"x" => -1}),
          block(%{"w" => 21}),
          block(%{"h" => 0}),
          block(%{"w" => 0}),
          block(%{"font_size" => 2}),
          block(%{"x" => "zero"})
        ] do
      assert {:error, _} = Trmnl.Layout.validate(%{"blocks" => [b]})
    end

    assert {:error, _} =
             Trmnl.Layout.validate(%{"blocks" => [block(), block(%{"id" => "two", "x" => 9})]})

    assert {:error, _} = Trmnl.Layout.validate(%{"blocks" => [block(), block(%{"x" => 10})]})
  end

  test "all block types support one-cell sizes and smaller text" do
    for kind <-
          ~w(agenda week month header text today_tomorrow dinner reminders countdowns family_note),
        font <- [12, 14] do
      layout = %{"blocks" => [block(%{"type" => kind, "w" => 1, "h" => 1, "font_size" => font})]}
      assert {:ok, ^layout} = Trmnl.Layout.validate(layout)
    end
  end

  test "Warsaw DST, exclusive all-day end and overnight events" do
    assert Trmnl.ScreenHTML.local("2026-03-29T01:30:00Z").hour == 3

    assert Trmnl.ScreenHTML.local("2026-10-25T00:30:00Z").utc_offset +
             Trmnl.ScreenHTML.local("2026-10-25T00:30:00Z").std_offset == 7200

    assert Trmnl.ScreenHTML.local("2026-10-25T01:30:00Z").std_offset == 0
    e = %{"start" => %{"date" => "2026-03-28"}, "end" => %{"date" => "2026-03-30"}}
    assert Trmnl.ScreenHTML.occurs?(e, ~D[2026-03-29])
    refute Trmnl.ScreenHTML.occurs?(e, ~D[2026-03-30])

    e = %{
      event()
      | "start" => %{"dateTime" => "2026-03-28T23:30:00+01:00"},
        "end" => %{"dateTime" => "2026-03-29T00:00:00+01:00"}
    }

    assert Trmnl.ScreenHTML.occurs?(e, ~D[2026-03-28])
    refute Trmnl.ScreenHTML.occurs?(e, ~D[2026-03-29])
  end

  test "screen escapes user content and uses seven columns starting today" do
    html =
      Trmnl.ScreenHTML.render(
        %{"blocks" => [block(%{"type" => "week", "w" => 20, "title" => "<script>bad</script>"})]},
        [],
        ~U[2026-03-29 10:00:00Z]
      )

    assert html =~ "&lt;script&gt;"
    refute html =~ "Pon 23.03"
    assert html =~ "Nd 29.03"
    assert html =~ "Sob 04.04"
    assert length(Regex.scan(~r/class=day/, html)) == 7
  end
end
