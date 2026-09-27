defmodule TrmnlWeb.DeviceController do
  use TrmnlWeb, :controller

  def setup(conn, _) do
    result =
      case Trmnl.Devices.authenticate(header(conn, "id"), header(conn, "access-token")) do
        {:ok, _} -> {:ok, header(conn, "access-token")}
        _ -> Trmnl.Devices.pair(header(conn, "id"))
      end

    case result do
      {:ok, token} ->
        json(conn, %{
          status: 200,
          api_key: token,
          friendly_id: "CAL001",
          image_url: image_url("setup-image.bmp"),
          filename: "setup"
        })

      _ ->
        unauthorized(conn)
    end
  end

  def display(conn, _) do
    authorized(conn, fn conn, d ->
      Trmnl.Devices.contact(d, header(conn, "battery-voltage"), header(conn, "rssi"))
      s = Trmnl.Publication.screen()

      json(conn, %{
        status: 0,
        image_url: image_url(),
        filename: s.image_hash || "setup",
        refresh_rate: Trmnl.Layout.poll_seconds(s.published),
        reset_firmware: false,
        update_firmware: false,
        firmware_url: nil,
        special_function: "sleep"
      })
    end)
  end

  def log(conn, params) do
    authorized(conn, fn conn, d ->
      Trmnl.Devices.contact(d, header(conn, "battery-voltage"), header(conn, "rssi"))

      # Arbitrary firmware messages can include credentials; store receipt and allowlisted telemetry only.
      Trmnl.Diagnostics.record(
        "device",
        Trmnl.Diagnostics.device_summary(params)
      )

      json(conn, %{status: 200})
    end)
  end

  def image(conn, %{"token" => token}) do
    case Phoenix.Token.verify(TrmnlWeb.Endpoint, "device-image", token, max_age: 86400) do
      {:ok, "screen"} ->
        png =
          Trmnl.Publication.screen().image ||
            File.read!(Application.app_dir(:trmnl, "priv/static/setup.png"))

        conn
        # Firmware v1.5.6 compares the complete header to "image/png".
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, png)

      _ ->
        unauthorized(conn)
    end
  end

  def image(conn, _), do: unauthorized(conn)

  def setup_image(conn, %{"token" => token}) do
    case Phoenix.Token.verify(TrmnlWeb.Endpoint, "device-image", token, max_age: 86400) do
      {:ok, "screen"} ->
        conn
        |> put_resp_content_type("image/bmp", nil)
        |> send_resp(200, File.read!(Application.app_dir(:trmnl, "priv/static/setup.bmp")))

      _ ->
        unauthorized(conn)
    end
  end

  def setup_image(conn, _), do: unauthorized(conn)

  defp image_url(path \\ "image") do
    token = Phoenix.Token.sign(TrmnlWeb.Endpoint, "device-image", "screen")
    Application.fetch_env!(:trmnl, :public_url) <> "/api/" <> path <> "?token=" <> token
  end

  defp authorized(conn, fun) do
    case Trmnl.Devices.authenticate(header(conn, "id"), header(conn, "access-token")) do
      {:ok, d} -> fun.(conn, d)
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn),
    do:
      conn
      |> put_status(401)
      |> json(%{status: 401, error: "Device is not authorized. Pair it in the dashboard."})

  defp header(conn, name), do: List.first(get_req_header(conn, name)) || ""
end
