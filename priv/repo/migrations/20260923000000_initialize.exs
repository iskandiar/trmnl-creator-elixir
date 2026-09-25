defmodule Trmnl.Repo.Migrations.Initialize do
  use Ecto.Migration

  def up do
    create table(:screens) do
      add :draft, :map, null: false, default: %{"blocks" => []}
      add :revision, :integer, null: false, default: 0
      add :published, :map
      add :image, :binary
      add :image_hash, :string
      add :published_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create constraint(:screens, :singleton, check: "id = 1")

    execute "INSERT INTO screens (id, draft, revision, inserted_at, updated_at) VALUES (1, '{\"blocks\": []}', 0, NOW(), NOW())"

    create table(:accounts) do
      add :label, :string, null: false
      add :tokens, :binary, null: false
      add :calendars, {:array, :map}, null: false, default: []
      add :selected, {:array, :string}, null: false, default: []
      add :events, {:array, :map}, null: false, default: []
      add :synced_at, :utc_datetime
      add :error, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:label])

    create table(:devices) do
      add :mac, :string, null: false
      add :token_hash, :binary
      add :pair_until, :utc_datetime
      add :last_contact, :utc_datetime
      add :battery, :string
      add :rssi, :string
      timestamps(type: :utc_datetime)
    end

    create constraint(:devices, :singleton, check: "id = 1")

    create table(:diagnostics) do
      add :kind, :string, null: false
      add :message, :string, null: false
      timestamps(type: :utc_datetime)
    end

    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
    drop table(:diagnostics)
    drop table(:devices)
    drop table(:accounts)
    drop table(:screens)
  end
end
