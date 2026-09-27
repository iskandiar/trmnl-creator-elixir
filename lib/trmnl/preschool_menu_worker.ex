defmodule Trmnl.PreschoolMenuWorker do
  use Oban.Worker,
    queue: :calendar,
    max_attempts: 1,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl true
  def perform(%Oban.Job{args: args}) do
    case Trmnl.PreschoolMenus.sync(args["manual"] == true) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
