defmodule Trmnl.SyncWorker do
  use Oban.Worker, queue: :calendar, max_attempts: 3, unique: [period: 240]
  @impl true
  def perform(_job) do
    results = Trmnl.Calendars.sync_all()

    if Enum.any?(results, &match?({:error, _}, &1)),
      do: {:error, "Calendar synchronization failed; see dashboard."},
      else: :ok
  end
end
