defmodule Trmnl.FamilyScheduleTest do
  use ExUnit.Case, async: true
  alias Trmnl.{FamilyItem, FamilySchedule, ScreenHTML, FamilyHTML}
  import Trmnl.Fixtures

  test "dated modules sort chronologically across month and year boundaries" do
    for kind <- ~w(dinner reminders countdowns) do
      items = [
        %FamilyItem{id: 1, kind: kind, title: "Later", date: ~D[2027-01-01]},
        %FamilyItem{id: 2, kind: kind, title: "Earlier", date: ~D[2026-12-31]}
      ]

      html = FamilyHTML.render(kind, items, ~D[2026-12-30], 7, [])
      {first, _} = :binary.match(html, "Earlier")
      {last, _} = :binary.match(html, "Later")
      assert first < last
    end
  end

  test "daily reminders cross DST on calendar dates and yearly Feb 29 uses Feb 28" do
    daily = %FamilyItem{date: ~D[2026-03-28], repeat: "daily", completed_on: ~D[2026-03-28]}
    assert FamilySchedule.due(daily, ~D[2026-03-29]) == ~D[2026-03-29]
    annual = %FamilyItem{date: ~D[2024-02-29], repeat: "yearly"}
    assert FamilySchedule.countdown_date(annual, ~D[2026-02-28]) == ~D[2026-02-28]
    assert FamilySchedule.countdown_date(annual, ~D[2026-03-01]) == ~D[2027-02-28]
    assert FamilySchedule.countdown_date(annual, ~D[2028-01-01]) == ~D[2028-02-29]
    future = %FamilyItem{date: ~D[2030-12-20], repeat: "yearly"}
    assert FamilySchedule.countdown_date(future, ~D[2026-01-01]) == ~D[2030-12-20]
  end

  test "dated notes include both endpoints and hide outside the window" do
    note = %FamilyItem{date: ~D[2026-09-24], end_date: ~D[2026-09-25]}
    assert FamilySchedule.active_note?(note, ~D[2026-09-24])
    assert FamilySchedule.active_note?(note, ~D[2026-09-25])
    refute FamilySchedule.active_note?(note, ~D[2026-09-26])
    refute FamilySchedule.active_note?(note, ~D[2026-09-23])
    assert FamilySchedule.active_note?(%FamilyItem{}, ~D[2026-09-24])
  end

  test "todo block hides completed tasks and ignores Google calendars" do
    layout = %{
      "blocks" => [
        block(%{
          "type" => "today_tomorrow",
          "title" => "Dzisiaj + jutro",
          "calendars" => ["selected"]
        })
      ]
    }

    events = [event() |> Map.put("calendar_key", "selected")]

    items = [
      %FamilyItem{
        id: 1,
        kind: "today_tomorrow",
        title: "Odbiór",
        date: ~D[2026-03-29],
        owner: "Tata"
      },
      %FamilyItem{
        id: 2,
        kind: "today_tomorrow",
        title: "Zrobione",
        date: ~D[2026-03-29],
        completed_on: ~D[2026-03-29]
      },
      %FamilyItem{id: 3, kind: "today_tomorrow", title: "Jutrzejsze", date: ~D[2026-03-30]}
    ]

    html = ScreenHTML.render(layout, events, ~U[2026-03-28 23:30:00Z], items)
    assert html =~ "Lista zadań"
    refute html =~ "☑"
    assert html =~ "☐"
    refute html =~ "Zrobione"
    assert html =~ "Tata"
    assert html =~ "Jutrzejsze"
    refute html =~ "Zażółć gęślą jaźń"
  end

  test "todo queue shows the first three unfinished entries regardless of date" do
    items = [
      %FamilyItem{id: 5, kind: "today_tomorrow", title: "Fifth"},
      %FamilyItem{id: 2, kind: "today_tomorrow", title: "Second", date: ~D[2027-02-01]},
      %FamilyItem{id: 1, kind: "today_tomorrow", title: "Done", completed_on: ~D[2026-12-30]},
      %FamilyItem{id: 4, kind: "today_tomorrow", title: "Fourth", date: ~D[2026-01-01]},
      %FamilyItem{id: 3, kind: "today_tomorrow", title: "Third"},
      %FamilyItem{id: 0, kind: "reminders", title: "Other module"}
    ]

    rows =
      FamilyHTML.render("today_tomorrow", items, ~D[2026-12-30], 7, [])
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".event")
      |> Enum.map(&LazyHTML.text/1)

    assert Enum.map(rows, &String.trim/1) == ["☐ Second", "☐ Third", "☐ Fourth"]
  end

  test "todo titles upgrade old defaults and preserve custom titles" do
    for title <- ["Dzisiaj + jutro", "3 zadania na dziś", "Zadania na tydzień", "Moje zadania"] do
      layout = %{"blocks" => [block(%{"type" => "today_tomorrow", "title" => title})]}
      [upgraded] = Trmnl.Layout.upgrade(layout)["blocks"]

      assert upgraded["title"] ==
               if(title == "Moje zadania", do: title, else: "Lista zadań")
    end
  end

  test "meals, countdowns, reminders and notes filter, prioritize and escape content" do
    today = ~D[2026-09-24]

    items = [
      %FamilyItem{id: 1, kind: "dinner", title: "Zupa", date: today, owner: "Mama"},
      %FamilyItem{id: 2, kind: "dinner", title: "Stary obiad", date: ~D[2026-09-23]},
      %FamilyItem{id: 3, kind: "reminders", title: "Zaległe książki", date: ~D[2026-09-22]},
      %FamilyItem{id: 4, kind: "reminders", title: "Gotowe", completed_on: today},
      %FamilyItem{id: 5, kind: "countdowns", title: "Urodziny", date: ~D[2026-09-25]},
      %FamilyItem{id: 6, kind: "countdowns", title: "Minęło", date: ~D[2026-09-23]},
      %FamilyItem{
        id: 7,
        kind: "family_note",
        title: "<script>abc</script>",
        body: "A & B",
        priority: 2
      },
      %FamilyItem{id: 8, kind: "family_note", title: "Wygasło", end_date: ~D[2026-09-23]}
    ]

    meal = FamilyHTML.render("dinner", items, today, 2, [])
    assert meal =~ "Zupa"
    assert meal =~ "Mama"
    refute meal =~ "Stary obiad"
    reminders = FamilyHTML.render("reminders", items, today, 7, [])
    assert reminders =~ "Zaległe · 22.09"
    refute reminders =~ "Gotowe"
    countdown = FamilyHTML.render("countdowns", items, today, 7, [])
    assert countdown =~ "Jutro!"
    refute countdown =~ "Minęło"
    note = FamilyHTML.render("family_note", items, today, 7, [])
    assert note =~ "&lt;script&gt;"
    assert note =~ "A &amp; B"
    refute note =~ "Wygasło"
  end
end
