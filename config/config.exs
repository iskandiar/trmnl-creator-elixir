import Config
config :trmnl, ecto_repos: [Trmnl.Repo], generators: [timestamp_type: :utc_datetime]

config :trmnl, TrmnlWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: TrmnlWeb.ErrorHTML, json: TrmnlWeb.ErrorJSON], layout: false],
  pubsub_server: Trmnl.PubSub,
  live_view: [signing_salt: "calendar-live"]

config :trmnl, Oban,
  repo: Trmnl.Repo,
  queues: [calendar: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 604_800},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", Trmnl.SyncWorker},
       {"* * * * *", Trmnl.ClockWorker},
       {"0 20 * * 0", Trmnl.PreschoolMenuWorker, timezone: "Europe/Warsaw"}
     ]}
  ]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, {:keep, []}

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
