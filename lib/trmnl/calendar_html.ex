defmodule Trmnl.CalendarHTML do
  alias Trmnl.ScreenHTML
  @weekdays ~w(Pon Wt Śr Czw Pt Sob Nd)
  @months ~w(Styczeń Luty Marzec Kwiecień Maj Czerwiec Lipiec Sierpień Wrzesień Październik Listopad Grudzień)

  def render("agenda", style, events, today, days) do
    Enum.map_join(0..(days - 1), "", fn offset ->
      date = Date.add(today, offset)
      rows = events |> Enum.filter(&ScreenHTML.occurs?(&1, date))

      if rows == [] do
        ""
      else
        heading = if style == "grouped", do: "<h3>#{label(date)}</h3>", else: ""
        heading <> Enum.map_join(rows, &ScreenHTML.event(&1, date, style != "grouped"))
      end
    end)
    |> empty()
  end

  def render("week", style, events, today, _) do
    days =
      Enum.map_join(0..6, "", fn offset ->
        date = Date.add(today, offset)
        rows = events |> Enum.filter(&ScreenHTML.occurs?(&1, date))

        content =
          if rows == [],
            do: "<p class=day-empty>—</p>",
            else: Enum.map_join(rows, &ScreenHTML.event(&1, date, false))

        "<div class='day #{if date == today, do: "is-today"}'><strong>#{label(date)}</strong><div>#{content}</div></div>"
      end)

    "<div class='week #{if style == "rows", do: "week-rows"}'>#{days}</div>"
  end

  def render("month", _, events, today, _) do
    first = Date.beginning_of_month(today)
    start = Date.add(first, 1 - Date.day_of_week(first))

    cells =
      Enum.map_join(0..41, "", fn offset ->
        date = Date.add(start, offset)
        count = Enum.count(events, &ScreenHTML.occurs?(&1, date))

        count_label =
          cond do
            Date.compare(date, Date.add(today, -7)) == :lt -> "<small>—</small>"
            count > 0 -> "<small>#{count} wyd.</small>"
            true -> ""
          end

        "<div class='month-day #{if date == today, do: "is-today"} #{if date.month != today.month, do: "outside"}'><b>#{date.day}</b>#{count_label}</div>"
      end)

    "<div class=month-heading>#{Enum.at(@months, today.month - 1)} #{today.year}</div><div class=month>" <>
      Enum.map_join(@weekdays, &"<strong>#{&1}</strong>") <>
      cells <> "</div><p class=month-legend>Liczba wydarzeń · — poza zakresem synchronizacji</p>"
  end

  defp label(date),
    do: "#{Enum.at(@weekdays, Date.day_of_week(date) - 1)} #{Calendar.strftime(date, "%d.%m")}"

  defp empty(""), do: "<p>Brak wydarzeń w wybranym okresie</p>"
  defp empty(html), do: html
end
