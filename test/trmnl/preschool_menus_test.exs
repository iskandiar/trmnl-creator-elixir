defmodule Trmnl.PreschoolMenusTest do
  use Trmnl.DataCase
  use Oban.Testing, repo: Trmnl.Repo

  alias Trmnl.{
    PreschoolMenus,
    PreschoolParser,
    PreschoolMenuWorker,
    PreschoolHTML,
    Family,
    RefreshWorker
  }

  @html File.read!("test/fixtures/preschool_menu.html")

  setup do
    keys = [:menu_source_req_options, :menu_ai_req_options, :gemini_api_key]
    previous = Map.new(keys, &{&1, Application.get_env(:trmnl, &1)})
    Application.put_env(:trmnl, :menu_source_req_options, plug: {Req.Test, :menu_source})
    Application.put_env(:trmnl, :menu_ai_req_options, plug: {Req.Test, :menu_ai})
    Application.put_env(:trmnl, :gemini_api_key, "")
    Req.Test.stub(:menu_source, &Plug.Conn.send_resp(&1, 200, @html))

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:trmnl, key),
          else: Application.put_env(:trmnl, key, value)
      end
    end)

    :ok
  end

  test "plain import is free, repeatable and never overwrites family meals" do
    {:ok, own} = Family.create("dinner", %{"title" => "Domowa zupa", "date" => "2026-09-28"})
    assert {:ok, :updated} = PreschoolMenus.sync(true)
    saved = PreschoolMenus.status()
    assert length(saved.days) == 2
    assert saved.imported_mode == "plain"
    assert saved.imported_at
    assert_enqueued(worker: RefreshWorker)
    assert {:ok, :unchanged} = PreschoolMenus.sync(true)
    assert PreschoolMenus.status().days == saved.days
    assert PreschoolMenus.status().imported_at == saved.imported_at
    assert Family.list("dinner") == [own]

    Req.Test.stub(
      :menu_source,
      &Plug.Conn.send_resp(&1, 200, String.replace(@html, "jabłko", "gruszka"))
    )

    assert {:ok, :updated} = PreschoolMenus.sync(true)
    assert hd(PreschoolMenus.status().days)["snack"] == "gruszka"
  end

  test "failed source or malformed menu preserves last successful snapshot" do
    assert {:ok, :updated} = PreschoolMenus.sync(true)
    saved = PreschoolMenus.status()

    for {code, body} <- [{503, "offline"}, {200, "<img src='menu.png'>"}] do
      Req.Test.stub(:menu_source, &Plug.Conn.send_resp(&1, code, body))
      assert {:error, _} = PreschoolMenus.sync(true)
      assert PreschoolMenus.status().days == saved.days
      assert PreschoolMenus.status().source_hash == saved.source_hash
      assert PreschoolMenus.status().error
    end
  end

  test "AI receives only public meal data, validates dates and skips unchanged content" do
    Application.put_env(:trmnl, :gemini_api_key, "test-key")
    {:ok, _} = PreschoolMenus.save_settings(%{"mode" => "gemini"})
    {:ok, days} = PreschoolParser.parse(@html)
    parent = self()

    Req.Test.stub(:menu_ai, fn conn ->
      assert conn.request_path =~ "gemini-2.5-flash-lite:generateContent"
      assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      [content] = request["contents"]
      [%{"text" => text}] = content["parts"]
      assert Jason.decode!(text) == days
      send(parent, :ai_called)
      ai_reply(conn, days)
    end)

    assert {:ok, :updated} = PreschoolMenus.sync(true)
    assert_receive :ai_called
    assert hd(PreschoolMenus.status().days)["original"] == hd(days)
    assert {:ok, :unchanged} = PreschoolMenus.sync(true)
    refute_received :ai_called

    Req.Test.stub(
      :menu_source,
      &Plug.Conn.send_resp(&1, 200, String.replace(@html, "jabłko", "banan"))
    )

    saved = PreschoolMenus.status()

    for output <- [
          [],
          [hd(days)],
          Enum.map(days, &Map.put(&1, "date", "2030-01-01")),
          Enum.map(days, &Map.put(&1, "lunch", ""))
        ] do
      Req.Test.stub(:menu_ai, &ai_reply(&1, output))
      assert {:error, _} = PreschoolMenus.sync(true)
      assert PreschoolMenus.status().days == saved.days
    end

    Req.Test.stub(
      :menu_ai,
      &Plug.Conn.send_resp(&1, 429, "test-key must never appear in diagnostics")
    )

    assert {:error, message} = PreschoolMenus.sync(true)
    refute message =~ "test-key"
    assert PreschoolMenus.status().days == saved.days
  end

  test "scheduled import is opt-in; manual requests deduplicate; AI requires a key" do
    assert {:error, :missing_key} = PreschoolMenus.save_settings(%{"mode" => "gemini"})
    assert {:error, _} = PreschoolMenus.save_settings(%{"mode" => "other"})
    assert {:ok, :disabled} = PreschoolMenus.sync()
    assert :ok = perform_job(PreschoolMenuWorker, %{})
    assert PreschoolMenus.status().days == []
    assert {:ok, first} = PreschoolMenus.enqueue()
    assert {:ok, second} = PreschoolMenus.enqueue()
    assert first.id == second.id
    assert :ok = perform_job(PreschoolMenuWorker, %{"manual" => true})
    assert length(PreschoolMenus.status().days) == 2
    assert {:ok, _} = PreschoolMenus.save_settings(%{"enabled" => "true"})
    assert {:ok, :unchanged} = PreschoolMenus.sync()
  end

  test "daily display filters actual dates and escapes imported content" do
    assert {:ok, :updated} = PreschoolMenus.sync(true)
    menu = PreschoolMenus.status()
    html = PreschoolHTML.render(menu, ~D[2026-09-29], 1)
    doc = LazyHTML.from_fragment(html)
    assert doc |> LazyHTML.query(".preschool-day") |> Enum.count() == 1
    assert doc |> LazyHTML.query(".preschool-day > strong") |> LazyHTML.text() == "Dzisiaj 29.09"
    assert doc |> LazyHTML.query(".preschool-meal") |> Enum.count() == 3
    assert PreschoolHTML.render(menu, ~D[2026-10-01], 7) =~ "Brak jadłospisu"
    day = hd(menu.days) |> Map.put("lunch", "<script>alert(1)</script>")
    assert PreschoolHTML.render(%{menu | days: [day]}, ~D[2026-09-28], 1) =~ "&lt;script&gt;"
  end

  test "today and tomorrow remain separate when the school has not published a day" do
    assert {:ok, :updated} = PreschoolMenus.sync(true)

    doc =
      PreschoolMenus.status()
      |> PreschoolHTML.render(~D[2026-09-27], 2)
      |> LazyHTML.from_fragment()

    columns = doc |> LazyHTML.query(".preschool-day") |> Enum.to_list()
    assert length(columns) == 2
    assert Enum.at(columns, 0) |> LazyHTML.query("strong") |> LazyHTML.text() == "Dzisiaj 27.09"

    assert Enum.at(columns, 0) |> LazyHTML.query("p") |> LazyHTML.text() ==
             "Brak opublikowanego menu"

    assert Enum.at(columns, 1) |> LazyHTML.query("strong") |> LazyHTML.text() == "Jutro 28.09"
    assert Enum.at(columns, 1) |> LazyHTML.query(".preschool-meal") |> Enum.count() == 3
  end

  defp ai_reply(conn, days) do
    Req.Test.json(conn, %{
      "candidates" => [
        %{"finishReason" => "STOP", "content" => %{"parts" => [%{"text" => Jason.encode!(days)}]}}
      ]
    })
  end
end
