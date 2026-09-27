defmodule Trmnl.PreschoolHTML do
  @weekdays ~w(Pon Wt Śr Czw Pt Sob Nd)

  def render(menu, today, days) do
    last = Date.add(today, days - 1) |> Date.to_iso8601()
    first = Date.to_iso8601(today)
    available = Enum.filter(menu.days, &(&1["date"] >= first and &1["date"] <= last))

    entries =
      if days == 2 do
        Enum.map([today, Date.add(today, 1)], fn date ->
          iso = Date.to_iso8601(date)
          Enum.find(available, &(&1["date"] == iso)) || %{"date" => iso}
        end)
      else
        available
      end

    if entries == [] do
      "<p>Brak jadłospisu na wybrane dni. Sprawdź import w ustawieniach.</p>" <> source(menu)
    else
      columns =
        Enum.map_join(entries, fn day ->
          date = Date.from_iso8601!(day["date"])

          meals =
            if day["breakfast"] do
              Enum.map_join(
                [{"breakfast", "Śniadanie"}, {"lunch", "Obiad"}, {"snack", "Podwieczorek"}],
                fn {field, label} ->
                  "<div class=preschool-meal><b>#{label}:</b> <p>#{escape(short(day[field]))}</p></div>"
                end
              )
            else
              "<p class=preschool-meal>Brak opublikowanego menu</p>"
            end

          label =
            cond do
              date == today -> "Dzisiaj"
              date == Date.add(today, 1) -> "Jutro"
              true -> Enum.at(@weekdays, Date.day_of_week(date) - 1)
            end

          "<div class=preschool-day><strong>#{label} #{Calendar.strftime(date, "%d.%m")}</strong>#{meals}</div>"
        end)

      "<div class=preschool-days style='grid-template-columns:repeat(#{length(entries)},minmax(0,1fr))'>#{columns}</div>" <>
        source(menu)
    end
  end

  def styles do
    """
    .preschool-days{display:grid;gap:5px}
    .preschool-day{min-width:0;border-right:1px solid black;padding-right:4px}
    .preschool-day:last-child{border:0}
    .preschool-day>strong{display:block;font-size:13px;line-height:15px;border-bottom:1px solid black;padding-bottom:1px}
    .preschool-meal{margin-top:3px;font-size:11px;line-height:11px;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:4;overflow:hidden}
    .preschool-meal b{font-size:10px}
    .preschool-meal p{display:inline}
    .preschool-source{display:block;margin-top:3px;font-size:8px;line-height:9px}
    """
  end

  defp source(menu) do
    suffix =
      if menu.imported_mode in ["gemini", "openrouter"], do: " · skrót AI", else: " · skrót"

    stale = if menu.error, do: " · zapisany jadłospis", else: ""

    "<small class=preschool-source>Przedszkole 123#{suffix}#{stale} · pełny jadłospis i alergeny na stronie przedszkola</small>"
  end

  defp short(value) do
    if String.length(value) > 100, do: String.slice(value, 0, 99) <> "…", else: value
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
