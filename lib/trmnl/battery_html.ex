defmodule Trmnl.BatteryHTML do
  # TRMNL OG estimate: https://help.trmnl.com/en/articles/10556850-device-battery-faq
  def percent(voltage) when is_binary(voltage) do
    case Float.parse(voltage) do
      {value, ""} when value > 0 and value <= 5.5 ->
        raw = Float.round((value - 3) / 0.012, 2)

        percent =
          cond do
            raw >= 88 -> 100
            raw >= 85 -> 95
            raw >= 83 -> 90
            raw >= 10 -> round(raw)
            true -> 1
          end

        {:ok, percent, value}

      _ ->
        :unknown
    end
  end

  def percent(_), do: :unknown

  def render(nil), do: "<p class=battery-empty>Połącz urządzenie.</p>"

  def render(device) do
    case percent(device.battery) do
      {:ok, percent, voltage} ->
        low = if percent <= 10, do: "<span class=battery-low>Naładuj baterię</span>", else: ""

        contact =
          if device.last_contact,
            do:
              device.last_contact
              |> DateTime.shift_zone!("Europe/Warsaw")
              |> Calendar.strftime("%d.%m %H:%M"),
            else: "brak"

        "<div class=battery><div class=battery-level>#{icon(percent)}<strong>≈#{percent}%</strong></div>" <>
          "<p>#{:erlang.float_to_binary(voltage, decimals: 2)} V #{low}</p><small>Kontakt: #{contact}</small></div>"

      :unknown ->
        "<p class=battery-empty>Brak odczytu baterii.<br>Poczekaj na kontakt.</p>"
    end
  end

  def styles do
    """
    .battery-level{display:flex;align-items:center;gap:6px}
    .battery-level strong{font-size:20px;line-height:21px;font-weight:500}
    .battery-icon{width:32px;height:18px;flex-shrink:0}
    .battery p{font-size:10px;line-height:12px;margin-top:1px}
    .battery small{display:block;font-size:9px;line-height:11px;margin-top:1px}
    .battery-low{font-weight:bold;white-space:nowrap}
    .battery-empty{font-size:11px;line-height:13px}
    """
  end

  defp icon(percent) do
    "<svg class=battery-icon viewBox='0 0 48 26' aria-hidden='true'><rect x='1' y='2' width='41' height='22' rx='3' fill='none' stroke='black' stroke-width='1.5'/><path d='M44 9h3v8h-3z' fill='black'/><rect x='5' y='7' width='#{max(1, round(percent / 100 * 33))}' height='12' rx='1' fill='black'/></svg>"
  end
end
