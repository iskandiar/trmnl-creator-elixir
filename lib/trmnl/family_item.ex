defmodule Trmnl.FamilyItem do
  use Ecto.Schema
  import Ecto.Changeset
  @kinds ~w(today_tomorrow dinner reminders countdowns family_note)
  @derive {Jason.Encoder,
           only: [
             :id,
             :kind,
             :title,
             :body,
             :owner,
             :date,
             :time,
             :end_date,
             :repeat,
             :completed_on,
             :priority
           ]}
  schema "family_items" do
    field :kind, :string
    field :title, :string
    field :body, :string, default: ""
    field :owner, :string, default: ""
    field :date, :date
    field :time, :time
    field :end_date, :date
    field :repeat, :string, default: "none"
    field :completed_on, :date
    field :priority, :integer, default: 0
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :body, :owner, :date, :time, :end_date, :repeat, :priority])
    |> validate_required([:kind, :title, :repeat, :priority])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 2000)
    |> validate_length(:owner, max: 80)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> normalize_optional()
    |> validate_kind()
    |> optimistic_lock(:lock_version)
  end

  defp normalize_optional(cs) do
    cs =
      Enum.reduce([:body, :owner], cs, fn field, cs ->
        if is_nil(get_field(cs, field)), do: put_change(cs, field, ""), else: cs
      end)

    if changed?(cs, :date) or changed?(cs, :repeat),
      do: put_change(cs, :completed_on, nil),
      else: cs
  end

  defp validate_kind(cs) do
    kind = get_field(cs, :kind)

    repeats =
      case kind do
        "reminders" -> ~w(none daily weekly)
        "countdowns" -> ~w(none yearly)
        _ -> ["none"]
      end

    cs = validate_inclusion(cs, :repeat, repeats)

    cs =
      if kind in ~w(today_tomorrow dinner countdowns) or get_field(cs, :repeat) != "none",
        do: validate_required(cs, [:date]),
        else: cs

    first = get_field(cs, :date)
    last = get_field(cs, :end_date)

    if first && last && Date.compare(first, last) == :gt,
      do: add_error(cs, :end_date, "must not be before the start date"),
      else: cs
  end
end
