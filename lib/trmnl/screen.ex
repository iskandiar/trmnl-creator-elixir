defmodule Trmnl.Screen do
  use Ecto.Schema

  schema "screens" do
    field :draft, :map, default: %{"blocks" => []}
    field :revision, :integer, default: 0
    field :published, :map
    field :image, :binary
    field :image_hash, :string
    field :published_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
