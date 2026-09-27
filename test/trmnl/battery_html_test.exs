defmodule Trmnl.BatteryHTMLTest do
  use Trmnl.DataCase
  alias Trmnl.{BatteryHTML, Devices, ScreenHTML}
  import Trmnl.Fixtures

  test "OG estimate handles low, normal and full voltage without inventing missing readings" do
    for {voltage, expected} <- [
          {"3.0", 1},
          {"3.12", 10},
          {"3.6", 50},
          {"3.9", 75},
          {"4.0", 90},
          {"4.03", 95},
          {"4.08", 100},
          {"4.2", 100}
        ] do
      assert {:ok, ^expected, _} = BatteryHTML.percent(voltage)
    end

    for voltage <- [nil, "", "bad", "3.9<script>", "0", "-1", "100"] do
      assert :unknown = BatteryHTML.percent(voltage)
    end
  end

  test "battery block renders paired telemetry and updates after a new device report" do
    layout = %{
      "blocks" => [block(%{"type" => "battery", "title" => "Bateria", "w" => 5, "h" => 3})]
    }

    assert {:ok, ^layout} = Trmnl.Layout.validate(layout)
    document = ScreenHTML.render(layout, []) |> LazyHTML.from_document()
    assert document |> LazyHTML.query(".battery-empty") |> LazyHTML.text() =~ "Połącz urządzenie"

    {:ok, device} = Devices.allow_pairing("AA:BB:CC:DD:EE:FF")
    assert BatteryHTML.render(device) =~ "Brak odczytu"
    device = Devices.contact(device, "3.9", "-52")
    document = ScreenHTML.render(layout, []) |> LazyHTML.from_document()
    assert document |> LazyHTML.query(".battery-level strong") |> LazyHTML.text() == "≈75%"
    assert document |> LazyHTML.query(".battery p") |> LazyHTML.text() =~ "3.90 V"
    assert document |> LazyHTML.query(".battery-icon") |> Enum.count() == 1

    Devices.contact(device, "3.1", "-52")
    document = ScreenHTML.render(layout, []) |> LazyHTML.from_document()
    assert document |> LazyHTML.query(".battery-low") |> LazyHTML.text() == "Naładuj baterię"
    assert document |> LazyHTML.query(".battery small") |> LazyHTML.text() =~ "Kontakt:"
  end
end
