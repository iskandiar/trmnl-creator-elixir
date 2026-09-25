ExUnit.start(exclude: if(System.get_env("RENDERER_TEST"), do: [], else: [renderer: true]))
Ecto.Adapters.SQL.Sandbox.mode(Trmnl.Repo, :manual)
