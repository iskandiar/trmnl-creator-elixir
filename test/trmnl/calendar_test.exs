defmodule Trmnl.CalendarTest do
  use Trmnl.DataCase
  alias Trmnl.{Calendars, Crypto, Google}
  import Trmnl.Fixtures

  setup do
    on_exit(fn ->
      Application.delete_env(:trmnl, :fail_sync)
      Application.delete_env(:trmnl, :google_req_options)
    end)

    :ok
  end

  test "multiple accounts, cancelled instances and failed sync preserving the snapshot" do
    a = account()
    b = account("two@example.com")
    assert :ok = Calendars.sync(a)
    assert :ok = Calendars.sync(b)
    assert length(Calendars.events()) == 2

    assert Enum.map(Calendars.events(), & &1["calendar_key"]) == [
             "#{a.id}:primary",
             "#{b.id}:primary"
           ]

    cached = Repo.get!(Trmnl.Account, a.id).events
    Application.put_env(:trmnl, :fail_sync, true)
    assert {:error, _} = Calendars.sync(a)
    assert Repo.get!(Trmnl.Account, a.id).events == cached
    assert Repo.get!(Trmnl.Account, a.id).error =~ "reconnect"
    Application.delete_env(:trmnl, :fail_sync)
    assert :ok = Calendars.sync(a)
    assert Repo.get!(Trmnl.Account, a.id).error == nil
  end

  test "tokens use authenticated encryption and are not inspectable" do
    a = account()
    refute a.tokens =~ "one@example.com"
    assert Crypto.decrypt(a.tokens)["refresh_token"] == "one@example.com"
    refute inspect(a) =~ "tokens:"
    <<head, tail::binary>> = a.tokens

    assert_raise FunctionClauseError, fn ->
      Crypto.decrypt(<<Bitwise.bxor(head, 1), tail::binary>>)
    end
  end

  test "real Google adapter follows calendar and event pages and requests expanded recurrence" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      page = conn.query_params["pageToken"]

      if String.ends_with?(conn.request_path, "/events") do
        assert conn.query_params["singleEvents"] == "true"
        assert conn.query_params["showDeleted"] == "true"
        assert conn.query_params["timeZone"] == "Europe/Warsaw"

        body =
          if page,
            do: %{"items" => [%{"id" => "cancelled-instance", "status" => "cancelled"}]},
            else: %{
              "items" => [Map.put(event("exception"), "recurringEventId", "series")],
              "nextPageToken" => "second"
            }

        Req.Test.json(conn, body)
      else
        Req.Test.json(
          conn,
          if(page,
            do: %{"items" => [%{"id" => "two"}]},
            else: %{"items" => [%{"id" => "one"}], "nextPageToken" => "second"}
          )
        )
      end
    end)

    Application.put_env(:trmnl, :google_req_options, plug: {Req.Test, __MODULE__})
    assert {:ok, [%{"id" => "one"}, %{"id" => "two"}]} = Google.calendars("secret")

    assert {:ok, [exception, cancelled]} =
             Google.events(
               "secret",
               "id@example.com",
               "2026-03-01T00:00:00Z",
               "2026-04-01T00:00:00Z"
             )

    assert exception["recurringEventId"] == "series"
    assert cancelled["status"] == "cancelled"
  end

  test "a later Google page failure does not return a partial success" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      if conn.query_params["pageToken"],
        do: Plug.Conn.send_resp(conn, 503, "credentials must not leak"),
        else: Req.Test.json(conn, %{"items" => [event()], "nextPageToken" => "next"})
    end)

    Application.put_env(:trmnl, :google_req_options, plug: {Req.Test, __MODULE__})
    assert {:error, {:http, 503}} = Google.events("secret", "primary", "from", "to")
  end

  test "actual paginated adapter replaces recurring exceptions and retains data on page failure" do
    a = account()
    Application.put_env(:trmnl, :google_client, Google)
    Application.put_env(:trmnl, :google_req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.put_env(:trmnl, :google_client, Trmnl.FakeGoogle)
      Application.delete_env(:trmnl, :fail_page)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      cond do
        conn.request_path == "/token" ->
          Req.Test.json(conn, %{"access_token" => "access"})

        String.ends_with?(conn.request_path, "calendarList") ->
          Req.Test.json(conn, %{"items" => [%{"id" => "primary"}]})

        conn.query_params["pageToken"] && Application.get_env(:trmnl, :fail_page) ->
          Plug.Conn.send_resp(conn, 503, "unavailable")

        conn.query_params["pageToken"] ->
          Req.Test.json(conn, %{
            "items" => [
              %{"id" => "cancelled-occurrence", "status" => "cancelled"},
              %{
                "id" => "all-day",
                "start" => %{"date" => "2026-03-29"},
                "end" => %{"date" => "2026-03-30"}
              }
            ]
          })

        true ->
          Req.Test.json(conn, %{
            "items" => [Map.put(event("moved-instance"), "recurringEventId", "series")],
            "nextPageToken" => "page2"
          })
      end
    end)

    assert :ok = Calendars.sync(a)
    cached = Repo.get!(Trmnl.Account, a.id).events
    assert Enum.map(cached, & &1["id"]) == ["moved-instance", "all-day"]
    Application.put_env(:trmnl, :fail_page, true)
    assert {:error, _} = Calendars.sync(a)
    assert Repo.get!(Trmnl.Account, a.id).events == cached
  end
end
