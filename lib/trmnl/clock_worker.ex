defmodule Trmnl.ClockWorker do
  use Oban.Worker, queue: :calendar, max_attempts: 2, unique: [period: 55]

  @impl true
  def perform(_) do
    if Trmnl.Layout.clock?(Trmnl.Publication.screen().published) do
      Trmnl.RefreshWorker.perform(%{})
    else
      :ok
    end
  end
end
