defmodule TrmnlWeb.DeviceControllerTest do
  use TrmnlWeb.ConnCase
  import Trmnl.Fixtures
  @mac "AA:BB:CC:DD:EE:FF"
  test "simulated device pairs, authenticates, downloads images, logs telemetry and keeps last successful display" do
    assert build_conn() |> get("/api/display") |> response(401)
    assert build_conn() |> put_req_header("id", @mac) |> get("/api/setup") |> response(401)
    assert {:ok, _} = Trmnl.Devices.allow_pairing(@mac)
    setup = build_conn() |> put_req_header("id", @mac) |> get("/api/setup") |> json_response(200)
    assert setup["status"] == 200
    setup_uri = URI.parse(setup["image_url"])

    assert <<"BM", _::binary>> =
             build_conn() |> get(setup_uri.path <> "?" <> setup_uri.query) |> response(200)

    assert build_conn() |> put_req_header("id", @mac) |> get("/api/setup") |> response(401)
    token = setup["api_key"]

    auth = fn ->
      build_conn() |> put_req_header("id", @mac) |> put_req_header("access-token", token)
    end

    display = auth.() |> get("/api/display") |> json_response(200)
    assert display["refresh_rate"] == 900

    png =
      build_conn()
      |> get(URI.parse(display["image_url"]).path <> "?" <> URI.parse(display["image_url"]).query)
      |> response(200)

    assert <<137, 80, 78, 71, _::binary>> = png
    assert {:ok, _} = Trmnl.Publication.save(%{"blocks" => [block()]}, 0)
    assert {:ok, published} = Trmnl.Publication.publish()
    display = auth.() |> get("/api/display") |> json_response(200)
    assert display["filename"] == published.image_hash

    assert build_conn()
           |> get(
             URI.parse(display["image_url"]).path <> "?" <> URI.parse(display["image_url"]).query
           )
           |> response(200) ==
             published.image

    assert auth.()
           |> put_req_header("battery-voltage", "3.9")
           |> put_req_header("rssi", "-52")
           |> post("/api/log", %{message: token})
           |> json_response(200) == %{"status" => 200}

    assert Trmnl.Devices.device().battery == "3.9"
    assert Trmnl.Devices.device().rssi == "-52"
    refute inspect(Trmnl.Diagnostics.recent()) =~ token

    assert build_conn()
           |> put_req_header("id", @mac)
           |> put_req_header("access-token", "bad")
           |> get("/api/display")
           |> response(401)

    assert build_conn() |> get("/api/image?token=bad") |> response(401)
  end

  test "expired pairing and different MAC cannot claim device" do
    {:ok, d} = Trmnl.Devices.allow_pairing(@mac)
    assert {:error, _} = Trmnl.Devices.pair("FF:FF:FF:FF:FF:FF")
    Trmnl.Repo.update!(Ecto.Changeset.change(d, pair_until: ~U[2020-01-01 00:00:00Z]))
    assert {:error, _} = Trmnl.Devices.pair(@mac)
  end
end
