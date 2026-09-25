defmodule Trmnl.Release do
  def migrate do
    Application.load(:trmnl)
    {:ok, _, _} = Ecto.Migrator.with_repo(Trmnl.Repo, &Ecto.Migrator.run(&1, :up, all: true))
  end
end
