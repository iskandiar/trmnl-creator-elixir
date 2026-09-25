defmodule Trmnl.Account do
  use Ecto.Schema
  @derive {Inspect, except: [:tokens, :events]}
  schema "accounts" do
    field :label, :string
    field :tokens, :binary
    field :calendars, {:array, :map}, default: []
    field :selected, {:array, :string}, default: []
    field :events, {:array, :map}, default: []
    field :synced_at, :utc_datetime
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
