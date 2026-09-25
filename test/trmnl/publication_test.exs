defmodule Trmnl.PublicationTest do
  use Trmnl.DataCase
  import Trmnl.Fixtures
  alias Trmnl.Publication

  setup do
    on_exit(fn -> Application.delete_env(:trmnl, :fail_render) end)
    :ok
  end

  test "draft isolation, atomic publication, retained last image and refreshed published content" do
    layout = %{"blocks" => [block()]}
    assert {:ok, _} = Publication.save(layout, 0)
    assert Publication.screen().published == nil
    assert {:ok, first} = Publication.publish()
    assert first.published == layout
    next = %{"blocks" => [block(%{"title" => "Draft only"})]}
    assert {:ok, _} = Publication.save(next, 1)
    assert Publication.screen().image == first.image
    assert {:error, _} = Publication.save(next, 1)
    assert {:error, message} = Publication.publish(1)
    assert message =~ "another tab"
    Application.put_env(:trmnl, :fail_render, true)
    assert {:error, _} = Publication.publish()
    assert Publication.screen().published == layout
    assert Publication.screen().image == first.image
    assert hd(Trmnl.Diagnostics.recent()).kind == "render"
    Application.delete_env(:trmnl, :fail_render)
    a = account()
    assert :ok = Trmnl.Calendars.sync(a)
    assert {:ok, refreshed} = Publication.refresh()
    assert refreshed.published == layout
    assert refreshed.draft == next
    refute refreshed.image == first.image
    assert {:ok, published} = Publication.publish()
    assert published.published == next
  end
end
