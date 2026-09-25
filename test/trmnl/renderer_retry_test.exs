defmodule Trmnl.RendererRetryTest do
  use ExUnit.Case

  setup do
    previous = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})
    on_exit(fn -> Req.default_options(previous) end)
    :ok
  end

  test "a busy renderer is retried and returns the eventual image" do
    png = <<137, 80, 78, 71, 13, 10, 26, 10>>
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 503, "Renderer busy; retry"))
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 200, png))
    assert {:ok, ^png} = Trmnl.Renderer.render(%{"blocks" => []}, [])
    Req.Test.verify!(__MODULE__)
  end

  test "a rendering failure is returned without retrying" do
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 500, "Render failed"))
    assert {:error, :renderer_unavailable} = Trmnl.Renderer.render(%{"blocks" => []}, [])
    Req.Test.verify!(__MODULE__)
  end
end
