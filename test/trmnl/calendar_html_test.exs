defmodule Trmnl.CalendarHTMLTest do
  use ExUnit.Case, async: true

  test "week shows today and the following six days across the year boundary in both layouts" do
    events =
      for {date, title} <- [
            {~D[2026-12-26], "Past event"},
            {~D[2026-12-27], "Today event"},
            {~D[2027-01-02], "Last day event"},
            {~D[2027-01-03], "Outside event"}
          ] do
        %{
          "summary" => title,
          "start" => %{"date" => Date.to_iso8601(date)},
          "end" => %{"date" => Date.to_iso8601(Date.add(date, 1))}
        }
      end

    for style <- ["list", "rows"] do
      document =
        Trmnl.CalendarHTML.render("week", style, events, ~D[2026-12-27], 7)
        |> LazyHTML.from_fragment()

      headings =
        document
        |> LazyHTML.query(".day > strong")
        |> Enum.map(&LazyHTML.text/1)

      assert headings == [
               "Nd 27.12",
               "Pon 28.12",
               "Wt 29.12",
               "Śr 30.12",
               "Czw 31.12",
               "Pt 01.01",
               "Sob 02.01"
             ]

      assert document |> LazyHTML.query(".is-today > strong") |> LazyHTML.text() == "Nd 27.12"

      rendered_events = document |> LazyHTML.query(".event") |> LazyHTML.text()
      assert rendered_events =~ "Today event"
      assert rendered_events =~ "Last day event"
      refute rendered_events =~ "Past event"
      refute rendered_events =~ "Outside event"
    end
  end
end
