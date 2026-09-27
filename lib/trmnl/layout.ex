defmodule Trmnl.Layout do
  @types ~w(weather agenda week month header text today_tomorrow dinner reminders countdowns family_note)
  # Retain the stored type key so existing blocks and family entries keep working.
  def upgrade(layout) do
    Map.update!(layout, "blocks", fn blocks ->
      Enum.map(blocks, fn b ->
        if b["type"] == "today_tomorrow" and
             b["title"] in ["Dzisiaj + jutro", "3 zadania na dziś", "Zadania na tydzień"],
           do: Map.put(b, "title", "Lista zadań"),
           else: b
      end)
    end)
  end

  def clock?(nil), do: false
  def clock?(layout), do: Enum.any?(layout["blocks"], &(&1["type"] == "header"))
  def poll_seconds(layout), do: if(clock?(layout), do: 240, else: 900)

  def validate(%{"blocks" => blocks} = layout) when is_list(blocks) and length(blocks) <= 40 do
    cond do
      not Enum.all?(blocks, &valid_block?/1) ->
        {:error, "Invalid block: use the 20×12 grid and a supported block type."}

      length(Enum.uniq_by(blocks, & &1["id"])) != length(blocks) ->
        {:error, "Block IDs must be unique."}

      overlaps?(blocks) ->
        {:error, "Blocks cannot overlap."}

      true ->
        {:ok, Map.take(layout, ["blocks"])}
    end
  end

  def validate(_), do: {:error, "Invalid layout."}

  defp valid_block?(b) when is_map(b) do
    b["type"] in @types and is_binary(b["id"]) and
      Enum.all?(~w(x y w h), &is_integer(b[&1])) and
      b["x"] >= 0 and b["y"] >= 0 and b["w"] >= 1 and b["h"] >= 1 and
      b["x"] + b["w"] <= 20 and b["y"] + b["h"] <= 12 and
      valid_weather?(b) and
      Map.get(b, "appearance", "classic") in ~w(classic minimal contrast) and
      Map.get(b, "density", "compact") in ~w(compact comfortable) and
      Map.get(b, "calendar_style", "list") in ~w(list grouped rows) and
      is_binary(Map.get(b, "text", "")) and byte_size(Map.get(b, "text", "")) <= 2000 and
      is_binary(Map.get(b, "title", "")) and byte_size(Map.get(b, "title", "")) <= 100 and
      is_list(Map.get(b, "calendars", [])) and
      Enum.all?(Map.get(b, "calendars", []), &is_binary/1) and
      Map.get(b, "font_size", 18) in [12, 14, 16, 18, 20, 24] and Map.get(b, "days", 7) in 1..30
  end

  defp valid_block?(_), do: false

  defp valid_weather?(%{"type" => "weather"} = block) do
    coords = [Map.get(block, "latitude", ""), Map.get(block, "longitude", "")]
    coords == ["", ""] or match?({:ok, _}, Trmnl.Weather.coordinates(block))
  end

  defp valid_weather?(_), do: true

  defp overlaps?([]), do: false

  defp overlaps?([a | rest]) do
    Enum.any?(rest, fn b ->
      a["x"] < b["x"] + b["w"] and a["x"] + a["w"] > b["x"] and a["y"] < b["y"] + b["h"] and
        a["y"] + a["h"] > b["y"]
    end) or overlaps?(rest)
  end
end
