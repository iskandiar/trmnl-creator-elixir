defmodule Trmnl.RefreshWorker do
  use Oban.Worker,
    queue: :calendar,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :retryable]]

  # Combine pending edits, but allow a follow-up job while a render is executing.
  @impl true
  def perform(_) do
    case Trmnl.Publication.refresh() do
      {:ok, _} -> :ok
      {:error, message} -> {:error, message}
    end
  end
end
