defmodule Trmnl.WeatherHTML do
  def render({:error, :location}, _now),
    do: "<p>Ustaw współrzędne w ustawieniach bloku Pogoda.</p>"

  def render({:error, _}, _now), do: "<p>Prognoza chwilowo niedostępna.</p>" <> attribution()

  def render({:ok, forecast}, now) do
    # Use the forecast hour containing now; never label a distant future point as current.
    current =
      forecast.rows
      |> Enum.filter(&(DateTime.diff(now, &1.at) in 0..3599))
      |> List.last()

    if current do
      stale = if forecast.stale, do: " · zapisane dane", else: ""

      "<div class=weather>" <>
        "<div class=weather-main><div><span class=weather-now>Teraz · prognoza</span><strong>#{number(current.temperature)}°C</strong></div><span class=weather-condition>#{condition(current.symbol)}</span></div>" <>
        "<p class=weather-details>Wiatr #{number(current.wind)} m/s · #{rain(current.rain)}</p>" <>
        graph(forecast.rows, current) <>
        tomorrow(forecast.rows, now) <>
        "<div class=weather-footer><small>Akt. #{hour(forecast.fetched_at)}#{stale}</small>#{attribution()}</div></div>"
    else
      render({:error, :unavailable}, now)
    end
  end

  def styles do
    """
    .weather{height:100%;display:flex;flex-direction:column;gap:2px}
    .weather-main{display:flex;align-items:center;justify-content:space-between;gap:8px}
    .weather-main strong{display:block;font-size:28px;line-height:1;font-weight:bold;white-space:nowrap}
    .weather-now{display:block;font-size:10px;line-height:11px}.weather-condition{font-size:12px;text-align:right;max-width:45%}
    .weather-details{font-size:10px;line-height:11px}.weather-chart{display:block;width:100%;flex:1;min-height:48px;overflow:visible}
    .weather-tomorrow{display:flex;justify-content:space-between;gap:4px;border-top:1px solid black;padding-top:2px;font-size:12px;line-height:14px}
    .weather-footer{display:flex;justify-content:space-between;flex-wrap:wrap;gap:2px;font-size:8px;line-height:9px}
    .weather-footer small,.weather-source{font-size:inherit}.weather-source a{color:black;text-decoration:none}
    """
  end

  defp tomorrow(rows, now) do
    date = now |> local() |> DateTime.to_date() |> Date.add(1)
    tomorrow = Enum.filter(rows, &(DateTime.to_date(local(&1.at)) == date))

    case tomorrow do
      [] ->
        "<div class=weather-tomorrow><strong>Jutro</strong><span>Brak prognozy</span></div>"

      rows ->
        temperatures = Enum.map(rows, & &1.temperature)
        first_hour = rows |> hd() |> Map.fetch!(:at) |> local() |> Map.fetch!(:hour)
        last_hour = rows |> List.last() |> Map.fetch!(:at) |> local() |> Map.fetch!(:hour)
        partial = if first_hour > 0 or last_hour < 23, do: " (część dnia)", else: ""

        "<div class=weather-tomorrow><strong>Jutro#{partial}</strong><span>min #{number(Enum.min(temperatures))}° · max #{number(Enum.max(temperatures))}°C</span></div>"
    end
  end

  defp graph(rows, current) do
    points = Enum.filter(rows, &(DateTime.diff(&1.at, current.at) in 0..86400))

    if length(points) < 2 do
      "<p class=weather-details>Brak danych o zmianie temperatury.</p>"
    else
      temperatures = Enum.map(points, & &1.temperature)
      low = Float.floor(Enum.min(temperatures) * 1.0)
      high = max(Float.ceil(Enum.max(temperatures) * 1.0), low + 2)
      x = fn at -> 32 + DateTime.diff(at, current.at) / 86400 * 278 end
      y = fn temperature -> 55 - (temperature - low) / (high - low) * 43 end

      line = Enum.map_join(points, " ", &"#{number(x.(&1.at))},#{number(y.(&1.temperature))}")

      dots =
        Enum.map_join(
          points,
          &"<circle cx='#{number(x.(&1.at))}' cy='#{number(y.(&1.temperature))}' r='1.5' fill='black'/>"
        )

      ticks =
        Enum.map_join([0, 8, 16, 24], fn offset ->
          at = DateTime.add(current.at, offset * 3600, :second)

          anchor =
            cond do
              offset == 0 -> "start"
              offset == 24 -> "end"
              true -> "middle"
            end

          label = Calendar.strftime(local(at), "%H:%M")

          day =
            case Date.diff(DateTime.to_date(local(at)), DateTime.to_date(local(current.at))) do
              0 -> "dziś"
              1 -> "jutro"
              _ -> Calendar.strftime(local(at), "%d.%m")
            end

          "<text x='#{number(x.(at))}' y='70' text-anchor='#{anchor}'>#{label}</text><text x='#{number(x.(at))}' y='82' text-anchor='#{anchor}'>#{day}</text>"
        end)

      "<svg class=weather-chart viewBox='0 0 320 86' preserveAspectRatio='none' role='img' aria-label='Prognoza temperatury na najbliższe 24 godziny'>" <>
        "<title>Temperatura w °C · najbliższe 24 godziny</title><g font-family='DejaVu Sans,sans-serif' font-size='10' fill='black'>" <>
        "<text x='1' y='16'>#{round(high)}°</text><text x='1' y='58'>#{round(low)}°</text>" <>
        "<path d='M32 12H310 M32 55H310' fill='none' stroke='black' stroke-width='0.5' stroke-dasharray='2 3'/>" <>
        "<polyline points='#{line}' fill='none' stroke='black' stroke-width='2' stroke-linejoin='round'/>#{dots}#{ticks}</g></svg>"
    end
  end

  defp local(at), do: DateTime.shift_zone!(at, "Europe/Warsaw")

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
