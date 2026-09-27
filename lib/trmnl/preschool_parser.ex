defmodule Trmnl.PreschoolParser do
  @meal_keys %{"śniadanie" => "breakfast", "obiad" => "lunch", "podwieczorek" => "snack"}
  @date ~r/\b(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})\b/u
  @meals ~r/(śniadanie|obiad|podwieczorek)\s*:\s*:?\s*(.*?)(?=(?:śniadanie|obiad|podwieczorek)\s*:|$)/iu

  def parse(html) when is_binary(html) and byte_size(html) <= 1_000_000 do
    rows =
      html
      |> String.replace(~r/<\/?(?:p|h[1-6]|td|div|br)\b[^>]*>/iu, " \\0 ")
      |> LazyHTML.from_document()
      |> LazyHTML.query("table tr")
      |> Enum.map(&(LazyHTML.text(&1) |> String.replace(~r/\s+/u, " ") |> String.trim()))
      |> Enum.filter(&Regex.match?(@date, &1))

    days = Enum.map(rows, &parse_day/1)

    if days != [] and length(days) <= 31 and Enum.all?(days, &is_map/1) and
         length(Enum.uniq_by(days, & &1["date"])) == length(days) do
      {:ok, Enum.sort_by(days, & &1["date"])}
    else
      {:error, :invalid_menu}
    end
  rescue
    _ -> {:error, :invalid_menu}
  end

  def parse(_), do: {:error, :invalid_menu}

  defp parse_day(text) do
    [_, day, month, year] = Regex.run(@date, text)
    meals = Regex.scan(@meals, text)

    fields =
      Map.new(meals, fn [_, kind, text] ->
        {@meal_keys[String.downcase(kind)], String.trim(text, " ")}
      end)

    with {:ok, date} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)),
         true <- map_size(fields) == 3 and length(meals) == 3,
         true <- Enum.all?(fields, fn {_, value} -> String.length(value) in 1..5000 end) do
      Map.put(fields, "date", Date.to_iso8601(date))
    else
      _ -> :invalid
    end
  end
end
