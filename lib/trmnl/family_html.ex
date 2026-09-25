defmodule Trmnl.FamilyHTML do
  alias Trmnl.FamilySchedule

  def render("today_tomorrow", items, today, _days, _events) do
    tasks =
      items
      |> Enum.filter(&(&1.kind == "today_tomorrow" and &1.date == today))
      |> Enum.sort_by(& &1.id)
      |> Enum.take(3)

    done = Enum.count(tasks, & &1.completed_on)

    rows =
      Enum.map_join(tasks, fn item ->
        mark = if item.completed_on, do: "☑", else: "☐"
        row(mark, item)
      end)

    "<h3>#{format_date(today)} · #{done}/3 wykonane</h3>" <>
      empty(rows, "Dodaj do 3 zadań na dziś w panelu rodzinnym.")
  end

  def render("dinner", items, today, days, _) do
    rows =
      items
      |> Enum.filter(&(&1.kind == "dinner" and in_window?(&1.date, today, days)))
      |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), time(&1.time), &1.id})
      |> Enum.map_join(&row(date_label(&1.date, today) <> optional_time(&1.time), &1))

    empty(rows, "Brak zaplanowanych posiłków")
  end

  def render("reminders", items, today, days, _) do
    items
    |> Enum.filter(&(&1.kind == "reminders"))
    |> Enum.map(&{&1, FamilySchedule.due(&1, today)})
    |> Enum.reject(fn {_, due} ->
      due == :completed or (due && Date.compare(due, Date.add(today, days - 1)) == :gt)
    end)
    |> Enum.sort_by(fn {i, due} ->
      {-(i.priority || 0), if(due, do: Date.to_gregorian_days(due), else: 0), i.id}
    end)
    |> Enum.map_join(fn {i, due} ->
      row(if(due, do: date_label(due, today), else: "Do zrobienia"), i)
    end)
    |> empty("Wszystko zrobione!")
  end

  def render("countdowns", items, today, _days, _) do
    items
    |> Enum.filter(&(&1.kind == "countdowns"))
    |> Enum.map(&{&1, FamilySchedule.countdown_date(&1, today)})
    |> Enum.filter(fn {_, date} -> Date.compare(date, today) != :lt end)
    |> Enum.sort_by(fn {i, date} -> {Date.to_gregorian_days(date), i.id} end)
    |> Enum.map_join(fn {i, date} ->
      label =
        case Date.diff(date, today) do
          0 -> "Dzisiaj!"
          1 -> "Jutro!"
          n -> "Za #{n} dni"
        end

      row(label <> " · " <> format_date(date), i)
    end)
    |> empty("Brak nadchodzących dat")
  end

  def render("family_note", items, today, _days, _) do
    items
    |> Enum.filter(&(&1.kind == "family_note" and FamilySchedule.active_note?(&1, today)))
    |> Enum.sort_by(&{-(&1.priority || 0), &1.id})
    |> Enum.map_join(&row("", &1))
    |> empty("Brak wiadomości")
  end

  defp row(label, item) do
    owner =
      if item.owner in [nil, ""],
        do: "",
        else: "<span class=family-owner> · #{escape(item.owner)}</span>"

    body = if item.body in [nil, ""], do: "", else: "<p>#{escape(item.body)}</p>"

    "<div class=event><strong>#{escape(label)}</strong> #{escape(item.title)}#{owner}#{body}</div>"
  end

  defp empty("", message), do: "<p>#{message}</p>"
  defp empty(rows, _), do: rows

  defp in_window?(date, today, days),
    do: Date.compare(date, today) != :lt and Date.compare(date, Date.add(today, days - 1)) != :gt

  defp time(nil), do: ""
  defp time(t), do: Calendar.strftime(t, "%H:%M")
  defp optional_time(nil), do: ""
  defp optional_time(t), do: " · " <> time(t)
  defp format_date(date), do: Calendar.strftime(date, "%d.%m")

  defp date_label(date, today) do
    case Date.diff(date, today) do
      0 -> "Dzisiaj"
      1 -> "Jutro"
      n when n < 0 -> "Zaległe · " <> format_date(date)
      _ -> format_date(date)
    end
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
