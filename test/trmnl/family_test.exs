defmodule Trmnl.FamilyTest do
  use Trmnl.DataCase
  use Oban.Testing, repo: Trmnl.Repo
  alias Trmnl.{Family, FamilySchedule, Publication, RefreshWorker}
  import Trmnl.Fixtures

  test "legacy dated todos allow more than three per date, edits, moves and completion undo" do
    tasks =
      for n <- 1..5 do
        assert {:ok, item} =
                 Family.create("today_tomorrow", %{"title" => "Task #{n}", "date" => "2026-09-25"})

        item
      end

    assert length(Family.list("today_tomorrow")) == 5
    {:ok, done} = Family.complete(hd(tasks))
    assert done.completed_on
    assert {:ok, edited} = Family.update(done, %{"title" => "Changed"})
    assert {:ok, restored} = Family.restore(edited)
    refute restored.completed_on

    {:ok, tomorrow} =
      Family.create("today_tomorrow", %{"title" => "Tomorrow", "date" => "2026-09-26"})

    assert {:ok, moved} = Family.update(tomorrow, %{"date" => "2026-09-25"})
    assert moved.date == ~D[2026-09-25]
    assert {:ok, _} = Family.delete(restored)
  end

  test "completing a todo promotes the next one and undo restores its place" do
    tasks =
      for n <- 1..4 do
        assert {:ok, task} = Family.create("today_tomorrow", %{"title" => "Todo #{n}"})
        assert is_nil(task.date)
        task
      end

    render_titles = fn ->
      Trmnl.FamilyHTML.render("today_tomorrow", Family.snapshot(), ~D[2026-09-27], 7, [])
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".event")
      |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    end

    assert render_titles.() == ["☐ Todo 1", "☐ Todo 2", "☐ Todo 3"]
    assert {:ok, done} = Family.complete(hd(tasks), ~D[2026-09-27])
    assert done.completed_on == ~D[2026-09-27]
    assert render_titles.() == ["☐ Todo 2", "☐ Todo 3", "☐ Todo 4"]
    assert List.last(Family.list("today_tomorrow")).id == done.id
    assert {:ok, _} = Family.restore(done)
    assert render_titles.() == ["☐ Todo 1", "☐ Todo 2", "☐ Todo 3"]

    for task <- Family.list("today_tomorrow"), do: Family.complete(task)
    assert render_titles.() == []
  end

  test "each content module persists independently of draft and published layout" do
    initial = Publication.screen()

    for kind <- Family.kinds() do
      assert {:ok, item} =
               Family.create(kind, %{
                 "title" => kind,
                 "date" => "2026-09-24",
                 "owner" => "Mama",
                 "body" => "Szczegóły"
               })

      assert Family.get(item.id).kind == kind
      assert Family.list(kind) == [item]
    end

    assert Publication.screen().draft == initial.draft
    assert Publication.screen().revision == initial.revision
    assert Publication.screen().published == nil
    assert_enqueued(worker: RefreshWorker)
    assert length(all_enqueued(worker: RefreshWorker)) == 1
    [running] = all_enqueued(worker: RefreshWorker)
    running |> Ecto.Changeset.change(state: "executing") |> Trmnl.Repo.update!()
    assert {:ok, _} = Family.create("family_note", %{"title" => "Edit during rendering"})
    [pending] = all_enqueued(worker: RefreshWorker)
    refute pending.id == running.id
  end

  test "validation, safe blank optional text, and stale edits" do
    assert {:error, cs} = Family.create("dinner", %{"title" => "Zupa"})
    assert errors_on(cs).date

    assert {:error, cs} =
             Family.create("reminders", %{"title" => "Podlać kwiaty", "repeat" => "weekly"})

    assert errors_on(cs).date

    assert {:error, cs} =
             Family.create("family_note", %{
               "title" => "Notatka",
               "date" => "2026-09-25",
               "end_date" => "2026-09-24"
             })

    assert errors_on(cs).end_date

    assert {:error, _} =
             Family.create("dinner", %{
               "title" => "Zupa",
               "date" => "2026-09-24",
               "repeat" => "yearly"
             })

    {:ok, item} = Family.create("family_note", %{"title" => "Hej", "body" => "", "owner" => ""})
    assert item.body == ""
    assert item.owner == ""
    assert {:ok, _} = Family.update(item, %{"title" => "Nowa"})
    assert {:error, stale} = Family.update(item, %{"title" => "Stara"})
    assert errors_on(stale).lock_version
    assert Family.get(item.id).title == "Nowa"
    assert {:ok, _} = item.id |> Family.get() |> Family.delete()
    assert Family.get(item.id) == nil
  end

  test "one-off and recurring reminders complete and restore by occurrence" do
    {:ok, once} = Family.create("reminders", %{"title" => "Książki"})
    {:ok, done} = Family.complete(once, ~D[2026-09-24])
    assert FamilySchedule.due(done, ~D[2026-09-25]) == :completed
    {:ok, restored} = Family.restore(done)
    assert FamilySchedule.due(restored, ~D[2026-09-25]) == nil

    {:ok, weekly} =
      Family.create("reminders", %{
        "title" => "Kosze",
        "date" => "2026-09-21",
        "repeat" => "weekly"
      })

    assert FamilySchedule.due(weekly, ~D[2026-09-24]) == ~D[2026-09-21]
    {:ok, weekly} = Family.complete(weekly, ~D[2026-09-24])
    assert FamilySchedule.due(weekly, ~D[2026-09-24]) == ~D[2026-09-28]
    assert FamilySchedule.due(weekly, ~D[2026-10-07]) == ~D[2026-10-05]
    {:ok, changed} = Family.update(weekly, %{"date" => "2026-09-25"})
    assert changed.completed_on == nil
    assert FamilySchedule.due(changed, ~D[2026-09-24]) == ~D[2026-09-25]
  end

  test "content refresh uses only the published layout and retains image on failure" do
    layout = %{"blocks" => [block(%{"type" => "family_note"})]}
    {:ok, _} = Publication.save(layout, 0)
    {:ok, original} = Publication.publish()
    {:ok, _} = Publication.save(%{"blocks" => []}, 1)
    {:ok, _} = Family.create("family_note", %{"title" => "Dziś u babci"})
    assert :ok = perform_job(RefreshWorker, %{})
    updated = Publication.screen()
    assert updated.published == layout
    assert updated.draft == %{"blocks" => []}
    assert updated.revision == 2
    refute updated.image == original.image
    Application.put_env(:trmnl, :fail_render, true)
    on_exit(fn -> Application.delete_env(:trmnl, :fail_render) end)
    {:ok, _} = Family.create("family_note", %{"title" => "Jutro spacer"})
    assert {:error, _} = perform_job(RefreshWorker, %{})
    assert Publication.screen().image == updated.image
    assert length(Family.list("family_note")) == 2
  end
end
