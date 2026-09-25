defmodule Trmnl.FamilySchedule do
  def today, do: DateTime.now!("Europe/Warsaw") |> DateTime.to_date()

  # Recurring chores carry the latest outstanding occurrence, rather than accumulating old copies.
  def due(%{repeat: repeat, date: date, completed_on: completed}, today)
      when repeat in ["daily", "weekly"] do
    interval = if repeat == "daily", do: 1, else: 7
    elapsed = max(Date.diff(today, date), 0)
    latest = Date.add(date, div(elapsed, interval) * interval)

    if completed && Date.compare(completed, latest) != :lt do
      Date.add(date, (div(Date.diff(completed, date), interval) + 1) * interval)
    else
      latest
    end
  end

  def due(%{repeat: "none", completed_on: completed}, _) when not is_nil(completed),
    do: :completed

  def due(%{date: date}, _), do: date

  def countdown_date(%{repeat: "yearly", date: date}, today) do
    year = max(date.year, today.year)
    candidate = anniversary(date, year)
    if Date.compare(candidate, today) == :lt, do: anniversary(date, year + 1), else: candidate
  end

  def countdown_date(%{date: date}, _), do: date

  defp anniversary(date, year) do
    first = Date.new!(year, date.month, 1)
    Date.new!(year, date.month, min(date.day, Date.days_in_month(first)))
  end

  def active_note?(item, today) do
    (is_nil(item.date) or Date.compare(item.date, today) != :gt) and
      (is_nil(item.end_date) or Date.compare(item.end_date, today) != :lt)
  end
end
