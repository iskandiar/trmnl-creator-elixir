defmodule Trmnl.RendererTest do
  use ExUnit.Case
  import Trmnl.Fixtures
  @moduletag :renderer
  test "all family modules render together with Polish content" do
    today = Trmnl.FamilySchedule.today()

    blocks =
      for {kind, x, y, w, h} <- [
            {"today_tomorrow", 0, 0, 10, 8},
            {"dinner", 10, 0, 10, 4},
            {"reminders", 10, 4, 10, 4},
            {"countdowns", 0, 8, 10, 4},
            {"family_note", 10, 8, 10, 4}
          ] do
        block(%{
          "id" => kind,
          "type" => kind,
          "title" => Trmnl.Family.label(kind),
          "x" => x,
          "y" => y,
          "w" => w,
          "h" => h
        })
      end

    items = [
      %Trmnl.FamilyItem{
        id: 1,
        kind: "today_tomorrow",
        title: "Odbiór dzieci",
        date: today,
        time: ~T[16:30:00],
        owner: "Anna"
      },
      %Trmnl.FamilyItem{
        id: 2,
        kind: "today_tomorrow",
        title: "Wizyta u babci",
        date: Date.add(today, 1),
        time: ~T[17:00:00]
      },
      %Trmnl.FamilyItem{
        id: 3,
        kind: "dinner",
        title: "Zupa pomidorowa",
        date: today,
        owner: "Tata",
        body: "Z ryżem"
      },
      %Trmnl.FamilyItem{id: 4, kind: "reminders", title: "Książki do biblioteki", owner: "Ola"},
      %Trmnl.FamilyItem{id: 5, kind: "countdowns", title: "Wakacje!", date: Date.add(today, 12)},
      %Trmnl.FamilyItem{
        id: 6,
        kind: "family_note",
        title: "Miłego dnia!",
        body: "Pamiętajcie o parasolach."
      }
    ]

    assert {:ok, png} = Trmnl.Renderer.render(%{"blocks" => blocks}, [], items)

    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 800::32, 480::32, 1, 0, _::binary>> =
             png

    File.mkdir_p!("artifacts")
    File.write!("artifacts/family-screen-local.png", png)
  end

  test "actual Chromium and ImageMagick render Polish week/agenda, monochrome dimensions and overflow" do
    layout = %{
      "blocks" => [
        block(%{
          "id" => "header",
          "type" => "header",
          "w" => 20,
          "h" => 2,
          "title" => "Rodzina · Zażółć gęślą jaźń"
        }),
        block(%{
          "id" => "week",
          "font_size" => 16,
          "type" => "week",
          "w" => 20,
          "h" => 6,
          "y" => 2,
          "title" => "Ten tydzień",
          "calendars" => ["1:dom", "2:praca"]
        }),
        block(%{
          "id" => "agenda",
          "w" => 12,
          "h" => 4,
          "y" => 8,
          "title" => "Nadchodzące wydarzenia",
          "calendars" => ["1:dom", "2:praca"]
        }),
        block(%{
          "id" => "note",
          "type" => "text",
          "x" => 12,
          "y" => 8,
          "w" => 8,
          "h" => 4,
          "title" => "Pamiętaj",
          "text" => "Książki do biblioteki\nSpacer po obiedzie"
        })
      ]
    }

    today = DateTime.now!("Europe/Warsaw") |> DateTime.to_date()
    monday = Date.add(today, 1 - Date.day_of_week(today))

    events =
      for i <- 0..6, j <- 1..5 do
        date = Date.add(monday, i) |> Date.to_iso8601()

        %{
          "id" => "#{i}-#{j}",
          "calendar_key" => if(rem(j, 2) == 0, do: "1:dom", else: "2:praca"),
          "summary" =>
            Enum.at(
              [
                "Śniadanie",
                "Przegląd projektu",
                "Lekcja języka",
                "Spotkanie zespołu",
                "Spacer z rodziną"
              ],
              j - 1
            ),
          "start" => %{
            "dateTime" => "#{date}T#{String.pad_leading(to_string(8 + j), 2, "0")}:00:00+02:00"
          },
          "end" => %{
            "dateTime" => "#{date}T#{String.pad_leading(to_string(9 + j), 2, "0")}:00:00+02:00"
          }
        }
      end

    {:ok, png} = Trmnl.Renderer.render(layout, events)

    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 800::32, 480::32, 1, 0, _::binary>> =
             png

    File.mkdir_p!("artifacts")
    File.write!("artifacts/calendar-screen.png", png)
    File.write!("artifacts/calendar-screen.html", Trmnl.ScreenHTML.render(layout, events))
  end
end
