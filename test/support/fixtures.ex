defmodule Trmnl.Fixtures do
  alias Trmnl.{Repo, Account, Crypto}

  def block(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => "one",
        "type" => "agenda",
        "x" => 0,
        "y" => 0,
        "w" => 10,
        "h" => 6,
        "title" => "Plan dnia",
        "text" => "",
        "calendars" => [],
        "font_size" => 18,
        "days" => 7
      },
      attrs
    )
  end

  def account(label \\ "one@example.com") do
    Repo.insert!(%Account{
      label: label,
      tokens: Crypto.encrypt(%{"refresh_token" => label}),
      calendars: [%{"id" => "primary", "summary" => "Dom"}],
      selected: ["primary"]
    })
  end

  def event(id \\ "event", title \\ "Zażółć gęślą jaźń") do
    %{
      "id" => id,
      "summary" => title,
      "status" => "confirmed",
      "start" => %{"dateTime" => "2026-03-29T01:30:00+01:00"},
      "end" => %{"dateTime" => "2026-03-29T03:30:00+02:00"}
    }
  end
end

defmodule Trmnl.FakeRenderer do
  def render(layout, events, family \\ []) do
    if Application.get_env(:trmnl, :fail_render),
      do: {:error, :offline},
      else:
        {:ok,
         File.read!("priv/static/setup.png") <>
           Jason.encode!(%{layout: layout, events: events, family: family})}
  end
end

defmodule Trmnl.FakeGoogle do
  def exchange(code), do: {:ok, %{"access_token" => code, "refresh_token" => code}}

  def refresh(token) do
    if Application.get_env(:trmnl, :fail_sync),
      do: {:error, :offline},
      else: {:ok, %{"access_token" => token}}
  end

  def calendars(token), do: {:ok, [%{"id" => token, "primary" => true, "summary" => "Główny"}]}

  def events(_, _, _, _),
    do: {:ok, [Trmnl.Fixtures.event(), %{"id" => "cancelled", "status" => "cancelled"}]}
end

defmodule Trmnl.BlockedRenderer do
  def render(layout, events, family \\ []) do
    send(Application.fetch_env!(:trmnl, :render_observer), {:render_started, self()})

    receive do
      :continue -> Trmnl.FakeRenderer.render(layout, events, family)
    after
      5000 -> {:error, :timeout}
    end
  end
end
