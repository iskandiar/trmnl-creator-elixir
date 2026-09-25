defmodule Trmnl.Publication do
  import Ecto.Query
  alias Trmnl.{Repo, Screen, Layout}
  def screen, do: Repo.get!(Screen, 1)

  def save(layout, revision) do
    with {:ok, layout} <- Layout.validate(layout) do
      {count, _} =
        Repo.update_all(from(s in Screen, where: s.id == 1 and s.revision == ^revision),
          set: [draft: layout, updated_at: now()],
          inc: [revision: 1]
        )

      if count == 1,
        do: {:ok, screen()},
        else: {:error, "Draft changed in another tab. Reload before saving."}
    end
  end

  def preview(layout) do
    with {:ok, valid} <- Layout.validate(layout),
         do: renderer().render(valid, Trmnl.Calendars.events(), Trmnl.Family.snapshot())
  end

  def publish(revision \\ nil), do: render_and_activate(:draft, revision)
  def refresh, do: render_and_activate(:published, nil)

  defp render_and_activate(source, revision) do
    result =
      Repo.transaction(
        fn ->
          s = Repo.one!(from s in Screen, where: s.id == 1, lock: "FOR UPDATE")
          if revision && revision != s.revision, do: Repo.rollback(:stale_draft)
          layout = Map.fetch!(s, source)

          if layout do
            case preview(layout) do
              {:ok, image} ->
                Repo.update!(
                  Ecto.Changeset.change(s,
                    published: layout,
                    image: image,
                    image_hash: Base.encode16(:crypto.hash(:sha256, image), case: :lower),
                    published_at: now()
                  )
                )

              {:error, _} ->
                Repo.rollback(:render_failed)
            end
          else
            s
          end
        end,
        timeout: 60_000
      )

    case result do
      {:error, :stale_draft} ->
        {:error, "Draft changed in another tab. Reload before publishing."}

      {:error, _} ->
        Trmnl.Diagnostics.record(
          "render",
          "Rendering failed. Check renderer health and retry publication. Previous image retained."
        )

        {:error, "Rendering failed; previous publication retained."}

      other ->
        other
    end
  end

  defp renderer, do: Application.get_env(:trmnl, :renderer, Trmnl.Renderer)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
