defmodule Trmnl.RendererAppearanceTest do
  use ExUnit.Case
  import Trmnl.Fixtures
  @moduletag :renderer

  test "real images for month, grouped agenda, week columns and week rows with a clock" do
    today = Trmnl.FamilySchedule.today()

    events =
      for n <- 0..6 do
        date = Date.add(today, n) |> Date.to_iso8601()

        %{
          "id" => "#{n}",
          "calendar_key" => "home",
          "summary" =>
            Enum.at(
              [
                "Odbiór dzieci",
                "Wizyta u babci",
                "Zakupy",
                "Basen",
                "Biblioteka",
                "Spacer",
                "Obiad rodzinny"
              ],
              n
            ),
          "start" => %{"dateTime" => "#{date}T16:00:00+02:00"},
          "end" => %{"dateTime" => "#{date}T17:00:00+02:00"}
        }
      end

    for {name, type, style, appearance} <- [
          {"month", "month", "list", "contrast"},
          {"agenda", "agenda", "grouped", "minimal"},
          {"week-columns", "week", "list", "classic"},
          {"week-rows", "week", "rows", "contrast"}
        ] do
      layout = %{
        "blocks" => [
          block(%{
            "id" => "clock",
            "type" => "header",
            "title" => "Rodzinny plan",
            "w" => 20,
            "h" => 2
          }),
          block(%{
            "id" => "calendar",
            "type" => type,
            "title" => "Kalendarz rodzinny",
            "w" => 20,
            "h" => 10,
            "y" => 2,
            "calendar_style" => style,
            "appearance" => appearance,
            "calendars" => ["home"]
          })
        ]
      }

      assert {:ok, _} = Trmnl.Layout.validate(layout)
      assert {:ok, png} = Trmnl.Renderer.render(layout, events)

      assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 800::32, 480::32, 1, 0,
               _::binary>> = png

      File.mkdir_p!("artifacts")
      File.write!("artifacts/ux-calendar-#{name}.png", png)
    end
  end
end
