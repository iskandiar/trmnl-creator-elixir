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
    keys = [:menu_source_req_options, :menu_ai_req_options, :openrouter_api_key]
    previous = Map.new(keys, &{&1, Application.get_env(:trmnl, &1)})
    Application.put_env(:trmnl, :menu_source_req_options, plug: {Req.Test, :menu_source})
    Application.put_env(:trmnl, :menu_ai_req_options, plug: {Req.Test, :menu_ai})
    Application.put_env(:trmnl, :openrouter_api_key, "")
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
    Application.put_env(:trmnl, :openrouter_api_key, "test-key")
    {:ok, _} = PreschoolMenus.save_settings(%{"mode" => "openrouter"})
    {:ok, days} = PreschoolParser.parse(@html)
    parent = self()

    Req.Test.stub(:menu_ai, fn conn ->
      assert conn.host == "openrouter.ai"
      assert conn.request_path == "/api/v1/chat/completions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["model"] == "openrouter/free"
      refute Map.has_key?(request, "models")
      assert request["provider"]["require_parameters"]
      assert request["response_format"]["type"] == "json_schema"
      assert request["response_format"]["json_schema"]["strict"]
      [%{"role" => "system"}, %{"role" => "user", "content" => text}] = request["messages"]
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
    assert message =~ "429"
    refute message =~ "test-key"
    assert PreschoolMenus.status().days == saved.days
  end

  test "scheduled import is opt-in; manual requests deduplicate; AI requires a key" do
    assert {:error, :missing_key} = PreschoolMenus.save_settings(%{"mode" => "openrouter"})
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

  test "OpenRouter diagnostics distinguish API failures and invalid output without leaking response data" do
    assert {:ok, :updated} = PreschoolMenus.sync(true)
    saved = PreschoolMenus.status().days
    Application.put_env(:trmnl, :openrouter_api_key, "test-key")
    {:ok, _} = PreschoolMenus.save_settings(%{"mode" => "openrouter"})

    for status <- [400, 401, 402, 403, 404, 429, 503] do
      Req.Test.stub(:menu_ai, fn conn ->
        conn
        |> Plug.Conn.put_status(status)
        |> Req.Test.json(%{"error" => %{"message" => "test-key"}})
      end)

      assert {:error, message} = PreschoolMenus.sync(true)
      assert message =~ "HTTP #{status}"
      refute message =~ "test-key"
      assert PreschoolMenus.status().days == saved
    end

    for {body, expected} <- [
          {%{"choices" => [%{"finish_reason" => "length"}]}, "limitu długości"},
          {%{"choices" => [%{"finish_reason" => "content_filter"}]}, "zablokowało"},
          {%{
             "choices" => [
               %{
                 "finish_reason" => "stop",
                 "message" => %{"content" => "not json test-key"}
               }
             ]
           }, "JSON"},
          {%{"choices" => []}, "nie pasuje"},
          {%{"error" => %{"code" => 429, "message" => "test-key"}}, "HTTP 429"}
        ] do
      Req.Test.stub(:menu_ai, &Req.Test.json(&1, body))
      assert {:error, message} = PreschoolMenus.sync(true)
      assert message =~ expected
      refute message =~ "test-key"
      assert PreschoolMenus.status().days == saved
    end
  end

  test "switching a saved Gemini menu to OpenRouter regenerates unchanged source and retains originals" do
    assert {:ok, :updated} = PreschoolMenus.sync(true)
    menu = PreschoolMenus.status()
    menu |> Ecto.Changeset.change(imported_mode: "gemini") |> Trmnl.Repo.update!()
    Application.put_env(:trmnl, :openrouter_api_key, "test-key")
    {:ok, _} = PreschoolMenus.save_settings(%{"mode" => "openrouter"})
    Req.Test.stub(:menu_ai, &ai_reply(&1, menu.days))

    assert {:ok, :updated} = PreschoolMenus.sync(true)
    updated = PreschoolMenus.status()
    assert updated.imported_mode == "openrouter"
    assert updated.source_hash == menu.source_hash
    assert Enum.map(updated.days, & &1["original"]) == menu.days
    assert {:ok, :unchanged} = PreschoolMenus.sync(true)
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
      "choices" => [
        %{
          "finish_reason" => "stop",
          "message" => %{"content" => Jason.encode!(%{"days" => days})}
        }
      ]
    })
  end
end
