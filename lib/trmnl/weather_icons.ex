defmodule Trmnl.WeatherIcons do
  # Original monochrome vectors, embedded so rendering needs no external image fetches.
  def condition(symbol) do
    night? = String.ends_with?(symbol, "_night")
    celestial = if night?, do: moon(), else: sun()

    {kind, paths} =
      cond do
        String.contains?(symbol, "thunder") ->
          {"thunder", cloud() <> "<path d='m25 27-6 9h6l-4 9 12-13h-7l5-5'/>"}

        String.contains?(symbol, "sleet") ->
          {"sleet", cloud() <> drops() <> "<path d='M35 35v8m-4-4h8'/>"}

        String.contains?(symbol, "snow") ->
          {"snow", cloud() <> "<path d='M14 34v9m-4-4h8m12-5v9m-4-4h8'/>"}

        String.contains?(symbol, "rain") ->
          {"rain", cloud() <> drops()}

        String.starts_with?(symbol, "clearsky") ->
          {if(night?, do: "moon", else: "sun"), celestial}

        String.starts_with?(symbol, "fair") or String.starts_with?(symbol, "partlycloudy") ->
          {"partly-cloudy", celestial <> cloud()}

        String.starts_with?(symbol, "fog") ->
          {"fog", cloud() <> "<path d='M6 35h36M10 41h28'/>"}

        String.starts_with?(symbol, "cloudy") ->
          {"cloud", cloud()}

        true ->
          {"unknown",
           "<text x='24' y='34' text-anchor='middle' stroke='none' fill='black' font-size='32'>?</text>"}
      end

    svg("weather-icon", kind, paths)
  end

  def rain,
    do:
      svg(
        "rain-icon",
        "drop",
        "<path d='M24 5C20 13 10 22 10 30a14 14 0 0 0 28 0c0-8-10-17-14-25Z'/>"
      )

  defp svg(class, kind, paths),
    do:
      "<svg class='#{class}' data-icon='#{kind}' viewBox='0 0 48 48' aria-hidden='true'><g stroke='black' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round' fill='none'>#{paths}</g></svg>"

  defp sun,
    do:
      "<circle cx='17' cy='16' r='8'/><path d='M17 2v3m0 22v3M3 16h3m22 0h3M7 6l2 2m16 16 2 2M7 26l2-2M25 8l2-2'/>"

  defp moon, do: "<path d='M22 3a14 14 0 1 0 12 22A15 15 0 0 1 22 3Z' fill='white'/>"

  defp cloud,
    do: "<path d='M12 30h25a8 8 0 0 0 0-16 12 12 0 0 0-22-3 9.5 9.5 0 0 0-3 19Z' fill='white'/>"

  defp drops, do: "<path d='m14 35-3 7m13-7-3 7m13-7-3 7'/>"
end
