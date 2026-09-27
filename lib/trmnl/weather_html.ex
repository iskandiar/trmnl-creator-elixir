defmodule Trmnl.WeatherHTML do
  def render({:error, :location}, _now),
    do: "<p>Ustaw współrzędne w ustawieniach bloku Pogoda.</p>"

  def render({:error, _}, _now), do: "<p>Prognoza chwilowo niedostępna.</p>" <> attribution()

  def render({:ok, forecast}, now) do
    rows = Enum.filter(forecast.rows, &(DateTime.diff(&1.at, now) >= -3600))

    case rows do
      [] ->
        render({:error, :unavailable}, now)

      [current | rest] ->
        upcoming = rest |> Enum.take_every(3) |> Enum.take(2)

        details =
          Enum.map_join(upcoming, fn row ->
            "<div class=weather-hour>#{hour(row.at)} · #{number(row.temperature)}°C · #{rain(row.rain)}</div>"
          end)

        stale = if forecast.stale, do: " · zapisane dane", else: ""

        "<div class=weather-main><strong>#{number(current.temperature)}°C</strong> #{condition(current.symbol)}</div>" <>
          "<p>#{hour(current.at)} · Wiatr #{number(current.wind)} m/s</p><p>#{rain(current.rain)}</p>" <>
          details <> "<small>Akt. #{hour(forecast.fetched_at)}#{stale}</small>" <> attribution()
    end
  end

  defp condition(symbol) do
    cond do
      String.contains?(symbol, "thunder") -> "Burze"
      String.contains?(symbol, "sleet") -> "Deszcz ze śniegiem"
      String.contains?(symbol, "snow") -> "Śnieg"
      String.contains?(symbol, "rain") -> "Deszcz"
      String.starts_with?(symbol, "clearsky") -> "Bezchmurnie"
      String.starts_with?(symbol, "fair") -> "Pogodnie"
      String.starts_with?(symbol, "partlycloudy") -> "Częściowe zachmurzenie"
      String.starts_with?(symbol, "cloudy") -> "Pochmurno"
      String.starts_with?(symbol, "fog") -> "Mgła"
      true -> "Prognoza"
    end
  end

  defp number(value), do: value |> Kernel.*(1.0) |> Float.round(1) |> Float.to_string()
  defp rain(nil), do: "Opady: brak danych"
  defp rain(value), do: "Opady #{number(value)} mm/1 h"

  defp hour(at),
    do: at |> DateTime.shift_zone!("Europe/Warsaw") |> Calendar.strftime("%d.%m %H:%M")

  defp attribution,
    do:
      "<small class=weather-source>Dane: MET Norway · <a href='https://creativecommons.org/licenses/by/4.0/'>CC BY 4.0</a></small>"
end
