defmodule Trmnl.Diagnostics do
  import Ecto.Query
  alias Trmnl.{Repo, Diagnostic}

  def record(kind, message) do
    Repo.insert!(%Diagnostic{kind: kind, message: String.slice(message, 0, 1000)})
    cutoff = Repo.all(from d in Diagnostic, order_by: [desc: d.id], offset: 200, select: d.id)
    Repo.delete_all(from d in Diagnostic, where: d.id in ^cutoff)
    :ok
  end

  def device_summary(params) do
    # Classify firmware messages without persisting arbitrary strings or secrets.
    payload = Jason.encode!(params) |> String.downcase()

    categories =
      for {needle, label} <- [
            {"wifi", "Wi-Fi connection"},
            {"http", "HTTP response"},
            {"image", "image download/decoding"},
            {"timeout", "network timeout"},
            {"memory", "device memory"}
          ],
          String.contains?(payload, needle),
          do: label

    if categories == [],
      do: "Device log received. Check device connectivity and last contact.",
      else:
        "Device reported: " <>
          Enum.join(categories, ", ") <>
          ". Check network, public URL and the current image; retry device refresh."
  end

  def recent, do: Repo.all(from d in Diagnostic, order_by: [desc: d.id], limit: 30)
end
