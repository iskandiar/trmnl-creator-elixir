defmodule TrmnlWeb.SessionController do
  use TrmnlWeb, :controller

  def new(conn, _), do: login(conn)

  defp login(conn, error \\ nil) do
    csrf = Plug.CSRFProtection.get_csrf_token()

    html(conn, """
    <!doctype html><html lang="pl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/assets/css/app.css"><title>TRMNL · Logowanie</title><main class="login"><p class="eyebrow">TRMNL / CALENDAR STUDIO</p><h1>Twój dzień.<br>Na jednym ekranie.</h1>#{if error, do: "<p class=error role=alert>#{error}</p>", else: ""}<form id="login-form" action="/login" method="post"><input type="hidden" name="_csrf_token" value="#{csrf}"><label>Hasło administratora<input type="password" name="password" required autocomplete="current-password"></label><button>Zaloguj</button></form></main></html>
    """)
  end

  def create(conn, %{"password" => password}) do
    # A fixed delay limits guessing without recording submitted credentials.
    Process.sleep(300)

    if Trmnl.Crypto.equal?(password, Application.fetch_env!(:trmnl, :admin_password)) do
      conn
      |> configure_session(renew: true)
      |> put_session(:admin, TrmnlWeb.Auth.issue())
      |> redirect(to: "/")
    else
      conn
      |> put_status(401)
      |> login("Nieprawidłowe hasło. Spróbuj ponownie.")
    end
  end

  def delete(conn, _),
    do: conn |> clear_session() |> configure_session(drop: true) |> redirect(to: "/login")
end
