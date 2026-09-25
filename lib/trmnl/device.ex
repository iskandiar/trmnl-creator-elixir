defmodule Trmnl.Device do
  use Ecto.Schema
  @derive {Inspect, except: [:token_hash]}
  schema "devices" do
    field :mac, :string
    field :token_hash, :binary
    field :pair_until, :utc_datetime
    field :last_contact, :utc_datetime
    field :battery, :string
    field :rssi, :string
    timestamps(type: :utc_datetime)
  end
end
