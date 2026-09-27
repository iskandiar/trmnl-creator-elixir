defmodule Trmnl.Family do
  import Ecto.Query
  alias Trmnl.{Repo, FamilyItem, FamilySchedule, RefreshWorker}
  def kinds, do: FamilyItem.kinds()

  def labels,
    do: [
      {"today_tomorrow", "Lista zadań"},
      {"dinner", "Plan posiłków"},
      {"reminders", "Obowiązki domowe"},
      {"countdowns", "Odliczanie"},
      {"family_note", "Wiadomości rodzinne"}
    ]

  def label(kind),
    do: labels() |> Enum.find_value(fn {key, label} -> if key == kind, do: label end)

  def list("today_tomorrow") do
    Repo.all(
      from i in FamilyItem,
        where: i.kind == "today_tomorrow",
        order_by: [asc: not is_nil(i.completed_on), asc: i.id]
    )
  end

  def list(kind),
    do:
      Repo.all(
        from i in FamilyItem,
          where: i.kind == ^kind,
          order_by: [desc: i.priority, asc: i.date, asc: i.time, asc: i.id]
      )

  def snapshot, do: Repo.all(FamilyItem)
  def get(id), do: Repo.get(FamilyItem, id)

  def new(kind),
    do: %FamilyItem{
      kind: kind,
      date: if(kind in ~w(dinner countdowns), do: FamilySchedule.today())
    }

  def change(item, attrs \\ %{}), do: FamilyItem.changeset(item, attrs)

  def create(kind, attrs)
      when kind in ~w(today_tomorrow dinner reminders countdowns family_note) do
    persist(fn -> Repo.insert(change(%FamilyItem{kind: kind}, attrs)) end)
  end

  def update(%FamilyItem{} = item, attrs) do
    persist(fn ->
      Repo.update(change(item, attrs),
        stale_error_field: :lock_version,
        stale_error_message: "changed in another tab; reopen the item"
      )
    end)
  end

  def delete(%FamilyItem{} = item),
    do:
      persist(fn ->
        Repo.delete(Ecto.Changeset.optimistic_lock(Ecto.Changeset.change(item), :lock_version),
          stale_error_field: :lock_version
        )
      end)

  def complete(%FamilyItem{kind: kind} = item, today \\ FamilySchedule.today())
      when kind in ["reminders", "today_tomorrow"] do
    due = FamilySchedule.due(item, today)

    if due == :completed do
      {:ok, item}
    else
      persist(fn ->
        Repo.update(
          item
          |> Ecto.Changeset.change(completed_on: due || today)
          |> Ecto.Changeset.optimistic_lock(:lock_version),
          stale_error_field: :lock_version
        )
      end)
    end
  end

  def restore(%FamilyItem{kind: kind} = item) when kind in ["reminders", "today_tomorrow"] do
    persist(fn ->
      Repo.update(
        item
        |> Ecto.Changeset.change(completed_on: nil)
        |> Ecto.Changeset.optimistic_lock(:lock_version),
        stale_error_field: :lock_version
      )
    end)
  end

  defp persist(fun) do
    result =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(73401925)")

        case fun.() do
          {:ok, item} ->
            # Enqueue in the same transaction: a saved change cannot miss its image refresh.
            case Oban.insert(RefreshWorker.new(%{})) do
              {:ok, _} -> item
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    if match?({:ok, _}, result),
      do: Phoenix.PubSub.broadcast(Trmnl.PubSub, "family", :family_changed)

    result
  end
end
