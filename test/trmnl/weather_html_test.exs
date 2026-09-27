defmodule Trmnl.WeatherHTMLTest do
  use ExUnit.Case, async: true
  alias Trmnl.WeatherHTML

  test "emphasizes the current hour, plots the next 24 hours and summarizes tomorrow only" do
    now = ~U[2026-09-27 10:30:00Z]

    rows =
      for offset <- -2..40, do: row(DateTime.add(~U[2026-09-27 10:00:00Z], offset * 3600), offset)

    document = render(rows, now)
    assert text(document, ".weather-main strong") == "0.0°C"
    assert text(document, ".weather-now") == "Teraz · prognoza"
    assert text(document, ".weather-tomorrow") =~ "min 12.0° · max 35.0°C"
    refute text(document, ".weather-tomorrow") =~ "część dnia"
    assert document |> LazyHTML.query(".weather-chart circle") |> Enum.count() == 25
    assert text(document, ".weather-chart") =~ "12:00dziś"
    assert text(document, ".weather-chart") =~ "12:00jutro"
  end

  test "tomorrow follows Warsaw dates across DST and includes both repeated hours" do
    now = ~U[2026-10-24 22:30:00Z]

    rows =
      for offset <- 0..49, do: row(DateTime.add(~U[2026-10-24 22:00:00Z], offset * 3600), offset)

    # Warsaw is already October 25; tomorrow begins 25 hours after local midnight.
    document = render(rows, now)
    assert text(document, ".weather-tomorrow") =~ "min 25.0° · max 48.0°C"
    refute text(document, ".weather-tomorrow") =~ "część dnia"
  end

  test "missing or partial tomorrow data is explicit and missing rain is not reported as zero" do
    now = ~U[2026-09-27 21:30:00Z]
    current = row(~U[2026-09-27 21:00:00Z], 8)
    document = render([current], now)
    assert text(document, ".weather-tomorrow") =~ "Brak prognozy"
    assert text(document, ".weather-details") =~ "Opady: brak danych"
    assert text(document, ".weather-details") =~ "Brak danych o zmianie temperatury"
    document = render([current, row(~U[2026-09-28 10:00:00Z], 15)], now)
    assert text(document, ".weather-tomorrow") =~ "Jutro (część dnia)"
    assert text(document, ".weather-tomorrow") =~ "min 15.0° · max 15.0°C"
  end

  test "constant and negative temperatures produce finite graph coordinates" do
    for temperature <- [-5, 0, 10] do
      rows =
        for hour <- 0..24,
            do: row(DateTime.add(~U[2026-09-27 10:00:00Z], hour * 3600), temperature)

      document = render(rows, ~U[2026-09-27 10:30:00Z])
      [line] = document |> LazyHTML.query("polyline") |> Enum.to_list()
      points = LazyHTML.attribute(line, "points") |> List.first() |> String.split()
      assert length(points) == 25

      for point <- points do
        [x, y] = point |> String.split(",") |> Enum.map(&String.to_float/1)
        assert x >= 32 and x <= 310
        assert y >= 12 and y <= 55
      end
    end
  end

  test "does not label a distant future or expired forecast as now" do
    now = ~U[2026-09-27 10:30:00Z]

    for at <- [~U[2026-09-27 09:00:00Z], ~U[2026-09-27 12:00:00Z]] do
      document = render([row(at, 12)], now)
      assert text(document, "p") =~ "niedostępna"
      assert document |> LazyHTML.query(".weather-main") |> Enum.empty?()
    end
  end

  defp render(rows, now) do
    WeatherHTML.render({:ok, %{rows: rows, fetched_at: now, stale: false}}, now)
    |> LazyHTML.from_fragment()
  end

  defp text(document, selector), do: document |> LazyHTML.query(selector) |> LazyHTML.text()

  defp row(at, temperature),
    do: %{at: at, temperature: temperature, rain: nil, wind: 2, symbol: "cloudy"}
end
