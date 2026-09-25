defmodule TrmnlWeb.Auth do
  import Plug.Conn
  import Phoenix.Controller
  def init(opts), do: opts

  def call(conn, _) do
    if valid?(get_session(conn, :admin)), do: conn, else: conn |> redirect(to: "/login") |> halt()
  end

  def issue do
    Phoenix.Token.sign(
      TrmnlWeb.Endpoint,
      "admin",
      Trmnl.Crypto.hash(Application.fetch_env!(:trmnl, :admin_password))
    )
  end

  def valid?(token) do
    case Phoenix.Token.verify(TrmnlWeb.Endpoint, "admin", token || "", max_age: 43_200) do
      {:ok, hash} -> hash == Trmnl.Crypto.hash(Application.fetch_env!(:trmnl, :admin_password))
      _ -> false
    end
  end

  def on_mount(:admin, _params, session, socket) do
    if valid?(session["admin"]),
      do: {:cont, socket},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
  end
end
