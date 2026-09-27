defmodule Trmnl.PreschoolMenu do
  use Ecto.Schema

  schema "preschool_menus" do
    field :enabled, :boolean, default: false
    field :mode, :string, default: "plain"
    field :days, {:array, :map}, default: []
    field :source_hash, :string
    field :imported_mode, :string
    field :checked_at, :utc_datetime
    field :imported_at, :utc_datetime
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
