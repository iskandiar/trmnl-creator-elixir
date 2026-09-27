defmodule Trmnl.Repo.Migrations.AddPreschoolMenuImport do
  use Ecto.Migration

  def change do
    create table(:preschool_menus) do
      add :enabled, :boolean, null: false, default: false
      add :mode, :string, null: false, default: "plain"
      add :days, {:array, :map}, null: false, default: []
      add :source_hash, :string
      add :imported_mode, :string
      add :checked_at, :utc_datetime
      add :imported_at, :utc_datetime
      add :error, :string
      timestamps(type: :utc_datetime)
    end

    create constraint(:preschool_menus, :single_menu, check: "id = 1")
  end
end
