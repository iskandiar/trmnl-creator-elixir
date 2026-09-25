defmodule TrmnlWeb.OAuthController do
  use TrmnlWeb, :controller

  def start(conn, _) do
    if Trmnl.Google.configured?() do
      state = Trmnl.Crypto.random()

      conn
      |> put_session(:oauth_state, {state, System.system_time(:second)})
      |> redirect(external: Trmnl.Google.authorization_url(state))
    else
      conn
      |> delete_session(:oauth_state)
      |> put_flash(
        :error,
        "Skonfiguruj Google OAuth: brakuje identyfikatora klienta lub sekretu. Instrukcja znajduje się przy kalendarzach."
      )
      |> redirect(to: "/")
    end
  end

  def callback(conn, params) do
    state = get_session(conn, :oauth_state)
    conn = delete_session(conn, :oauth_state)

    valid =
      case state do
        {expected, time} ->
          Trmnl.Crypto.equal?(expected, params["state"]) and
            System.system_time(:second) - time < 600

        _ ->
          false
      end

    if valid and is_binary(params["code"]) do
      case Trmnl.Calendars.connect(params["code"]) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Połączono konto Google. Wybierz kalendarze.")
          |> redirect(to: "/")

        {:error, message} ->
          conn |> put_flash(:error, message) |> redirect(to: "/")
      end
    else
      conn
      |> put_status(400)
      |> text("OAuth state invalid or expired. Start connection again from the dashboard.")
    end
  end
end
