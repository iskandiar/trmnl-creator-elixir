defmodule Trmnl.Repo.Migrations.AddFamilyItems do
  use Ecto.Migration

  def change do
    create table(:family_items) do
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false, default: ""
      add :owner, :string, null: false, default: ""
      add :date, :date
      add :time, :time
      add :end_date, :date
      add :repeat, :string, null: false, default: "none"
      add :completed_on, :date
      add :priority, :integer, null: false, default: 0
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:family_items, [:kind, :date])

    create constraint(:family_items, :valid_kind,
             check:
               "kind IN ('today_tomorrow', 'dinner', 'reminders', 'countdowns', 'family_note')"
           )
  end
end
