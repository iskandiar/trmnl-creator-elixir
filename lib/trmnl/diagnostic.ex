defmodule Trmnl.Diagnostic do
  use Ecto.Schema

  schema "diagnostics" do
    field :kind, :string
    field :message, :string
    timestamps(type: :utc_datetime)
  end
end
