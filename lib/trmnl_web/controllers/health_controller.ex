defmodule TrmnlWeb.HealthController do
  use TrmnlWeb, :controller

  def show(conn, _) do
    Ecto.Adapters.SQL.query!(Trmnl.Repo, "SELECT 1", [])
    json(conn, %{status: "ok"})
  end
end
