defmodule Trmnl.Calendars do
  import Ecto.Query
  alias Trmnl.{Repo, Account, Crypto}
  def client, do: Application.get_env(:trmnl, :google_client, Trmnl.Google)
  def accounts, do: Repo.all(from a in Account, order_by: a.id)

  def options do
    for a <- accounts(),
        c <- a.calendars,
        c["id"] in a.selected,
        do: {"#{a.id}:#{c["id"]}", "#{a.label} · #{c["summary"]}"}
  end

  def connect(code) do
    with {:ok, tokens} <- client().exchange(code),
         {:ok, calendars} <- client().calendars(tokens["access_token"]),
         %{"id" => label} <- Enum.find(calendars, & &1["primary"]) do
      old = Repo.get_by(Account, label: label)
      previous = if old, do: Crypto.decrypt(old.tokens), else: %{}
      merged = Map.merge(previous, tokens)

      if is_binary(merged["refresh_token"]) do
        (old || %Account{})
        |> Ecto.Changeset.change(
          label: label,
          tokens: Crypto.encrypt(merged),
          calendars: calendars,
          error: nil
        )
        |> Repo.insert_or_update()
      else
        {:error, "Google did not issue a refresh token. Reconnect and grant offline access."}
      end
    else
      _ ->
        {:error, "Google connection failed. Check OAuth settings and grant calendar read access."}
    end
  end

  def select(id, selected) do
    a = Repo.get!(Account, id)
    valid = Enum.map(a.calendars, & &1["id"])

    if Enum.all?(selected, &(&1 in valid)) do
      Repo.update(Ecto.Changeset.change(a, selected: Enum.uniq(selected)))
    else
      {:error, "Unknown calendar."}
    end
  end

  def sync_all do
    results = Enum.map(accounts(), &sync/1)
    Trmnl.Publication.refresh()
    results
  end

  def sync(account) do
    # Lock the account through the fetch, so selection changes cannot be overwritten.
    result =
      Repo.transaction(fn ->
        a = Repo.one!(from a in Account, where: a.id == ^account.id, lock: "FOR UPDATE")
        tokens = Crypto.decrypt(a.tokens)

        with {:ok, fresh} <- client().refresh(tokens["refresh_token"]),
             {:ok, calendars} <- client().calendars(fresh["access_token"]),
             {:ok, events} <- fetch_selected(a, fresh["access_token"]) do
          Repo.update!(
            Ecto.Changeset.change(a,
              tokens: Crypto.encrypt(Map.merge(tokens, fresh)),
              calendars: calendars,
              events: events,
              synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
              error: nil
            )
          )
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, _} ->
        :ok

      {:error, _} ->
        message =
          "Sync failed for #{account.label}. Check connectivity; reconnect Google if access was revoked, then retry sync. Cached events retained."

        Repo.update_all(from(a in Account, where: a.id == ^account.id), set: [error: message])
        Trmnl.Diagnostics.record("sync", message)
        {:error, message}
    end
  rescue
    _ ->
      message =
        "Sync failed. Check token encryption key and Google connection; cached events retained."

      Repo.update_all(from(a in Account, where: a.id == ^account.id), set: [error: message])
      Trmnl.Diagnostics.record("sync", message)
      {:error, message}
  end

  defp fetch_selected(a, token) do
    now = DateTime.utc_now()
    from = DateTime.add(now, -7, :day) |> DateTime.to_iso8601()
    until = DateTime.add(now, 35, :day) |> DateTime.to_iso8601()

    Enum.reduce_while(a.selected, {:ok, []}, fn id, {:ok, all} ->
      case client().events(token, id, from, until) do
        {:ok, events} ->
          events =
            events
            |> Enum.reject(&(&1["status"] == "cancelled"))
            |> Enum.map(&Map.put(&1, "calendar_key", "#{a.id}:#{id}"))

          {:cont, {:ok, all ++ events}}

        error ->
          {:halt, error}
      end
    end)
  end

  def events, do: accounts() |> Enum.flat_map(& &1.events)
end
