defmodule Trmnl.ScreenHTML do
  @days ~w(Poniedziałek Wtorek Środa Czwartek Piątek Sobota Niedziela)
  def render(layout, events, now \\ DateTime.utc_now(), family \\ []) do
    layout = Trmnl.Layout.upgrade(layout)
    local_now = DateTime.shift_zone!(now, "Europe/Warsaw")
    today = DateTime.to_date(local_now)
    blocks = Enum.map_join(layout["blocks"], "", &block(&1, events, today, family, local_now))

    """
    <!doctype html><html lang="pl"><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;background:white;color:black;font-family:'DejaVu Sans',sans-serif;width:800px;height:480px;overflow:hidden}
    section{position:absolute;border:1px solid black;padding:5px;overflow:hidden;background:white}
    h2{font-size:18px;margin:0 0 3px;line-height:22px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .content{height:calc(100% - 25px);overflow:hidden;line-height:1.2}
    .event{border-top:1px solid black;padding:2px 0;overflow-wrap:anywhere}.time{font-weight:bold}.week{display:grid;grid-template-columns:repeat(7,1fr);gap:4px;height:100%}
    .day{overflow:hidden;border-right:1px solid black;padding-right:4px}.day strong{font-size:16px}.day .event{font-size:inherit}
    .weather-main strong{font-size:26px}.weather-hour{border-top:1px solid black;padding-top:2px;margin-top:2px}.weather-source{display:block;font-size:10px}.weather-source a{color:black}
    .overflow{position:absolute;bottom:0;right:4px;background:white;border-top:1px solid black;font-size:14px;font-weight:bold;display:none;padding:1px 5px}
    h3{font-size:inherit;margin:6px 0 3px}.family-owner{font-weight:bold}
    p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}
    .compact{padding:3px}.compact h2{font-size:14px;line-height:17px;margin-bottom:2px}
    .compact .content{height:calc(100% - 19px);line-height:1.1}.compact .event{padding:1px 0}
    .compact h3{margin:3px 0 1px}.compact .week{gap:2px}.compact .day{padding-right:2px}
    .compact .day strong{font-size:12px}.compact .day-empty{font-size:12px}
    .compact .week-rows .day{grid-template-columns:72px minmax(0,1fr);gap:3px;padding:1px 0}
    .compact .clock-date{font-size:12px}.compact .clock-time{font-size:20px}.compact .clock-time small{font-size:10px}
    .comfortable{padding:8px}.comfortable .event{padding:4px 0}.comfortable .content{line-height:1.3}
    .minimal{border-color:transparent;border-top:1px solid black}.minimal .event{border:0}
    .contrast h2{background:black;color:white;padding:0 4px}
    .clock{display:flex;justify-content:space-between;align-items:center;gap:8px;height:100%}
    .clock-date{font-size:16px}.clock-date span{display:block}.clock-time{font-size:26px;font-weight:bold;white-space:nowrap;line-height:1}
    .clock-time small{font-size:12px;display:block;text-align:right;margin-top:3px}
    .week-rows{display:block}.week-rows .day{display:grid;grid-template-columns:95px 1fr;gap:6px;border:0;border-top:1px solid black;padding:2px 0}
    .week-rows .event{border:0}.is-today>strong{background:black;color:white;padding:1px 3px}.day-empty{font-size:14px}
    .month{display:grid;grid-template-columns:repeat(7,1fr);grid-template-rows:18px repeat(6,minmax(0,1fr));height:calc(100% - 40px);gap:2px;font-size:14px}
    .month>strong{text-align:center}.month-day{border-top:1px solid black;padding:2px;overflow:hidden}.month-day small{display:block;font-size:10px}
    .month-day.is-today{background:black;color:white}.outside b{font-weight:normal}.month-heading{font-size:16px;font-weight:bold;margin-bottom:3px}.month-legend{font-size:11px;margin-top:3px}
    </style><body>#{blocks}</body></html>
    """
  end

  defp block(b, events, today, family, now) do
    selected = Map.get(b, "calendars", [])
    events = events |> Enum.filter(&(&1["calendar_key"] in selected)) |> Enum.sort_by(&sort_key/1)
    title = Map.get(b, "title", "")

    content =
      case b["type"] do
        kind when kind in ~w(today_tomorrow dinner reminders countdowns family_note) ->
          Trmnl.FamilyHTML.render(kind, family, today, Map.get(b, "days", 7), events)

        "header" ->
          "<div class=clock><div class=clock-date>#{Enum.at(@days, Date.day_of_week(today) - 1)}<span>#{Calendar.strftime(today, "%d.%m.%Y")}</span></div><div class=clock-time>#{Calendar.strftime(now, "%H:%M")}<small>±5 min</small></div></div>"

        "weather" ->
          Trmnl.WeatherHTML.render(Trmnl.Weather.forecast(b), now)

        "text" ->
          "<p>#{escape(Map.get(b, "text", ""))}</p>"

        kind when kind in ~w(agenda week month) ->
          Trmnl.CalendarHTML.render(
            kind,
            Map.get(b, "calendar_style", "list"),
            events,
            today,
            Map.get(b, "days", 7)
          )
      end

    "<section class='#{Map.get(b, "appearance", "classic")} #{Map.get(b, "density", "compact")}' style='left:#{b["x"] * 40}px;top:#{b["y"] * 40}px;width:#{b["w"] * 40}px;height:#{b["h"] * 40}px;font-size:#{Map.get(b, "font_size", 18)}px'><h2>#{escape(title)}</h2><div class=content>#{content}</div><span class=overflow>Więcej ↓</span></section>"
  end

  def occurs?(%{"start" => %{"date" => first}, "end" => %{"date" => last}}, day) do
    Date.compare(day, Date.from_iso8601!(first)) != :lt and
      Date.compare(day, Date.from_iso8601!(last)) == :lt
  end

  def occurs?(%{"start" => %{"dateTime" => first}, "end" => %{"dateTime" => last}}, day) do
    start_at = local(first)
    end_at = local(last) |> DateTime.add(-1, :second)

    Date.compare(day, DateTime.to_date(start_at)) != :lt and
      Date.compare(day, DateTime.to_date(end_at)) != :gt
  end

  def occurs?(_, _), do: false

  def local(value) do
    {:ok, dt, _} = DateTime.from_iso8601(value)
    DateTime.shift_zone!(dt, "Europe/Warsaw")
  end

  def event(e, day, with_date) do
    time =
      if e["start"]["date"],
        do: "Cały dzień",
        else: Calendar.strftime(local(e["start"]["dateTime"]), "%H:%M")

    date = if with_date, do: Calendar.strftime(day, "%d.%m") <> " · ", else: ""

    "<div class=event><span class=time>#{date}#{time}</span> #{escape(e["summary"] || "Bez tytułu")}</div>"
  end

  defp sort_key(%{"start" => %{"date" => date}}), do: {date, -1}

  defp sort_key(%{"start" => %{"dateTime" => value}}) do
    dt = local(value)
    {dt |> DateTime.to_date() |> Date.to_iso8601(), DateTime.to_unix(dt)}
  end

  defp sort_key(_), do: {"", -1}

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
