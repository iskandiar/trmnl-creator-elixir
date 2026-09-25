import Config

config :trmnl, Trmnl.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 55432,
  database: "trmnl_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :trmnl, TrmnlWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test-secret-", 8),
  server: false

config :trmnl, Oban, testing: :manual

config :trmnl,
  admin_password: "test-password",
  encryption_key: :crypto.hash(:sha256, "test"),
  renderer: Trmnl.FakeRenderer,
  google_client: Trmnl.FakeGoogle,
  public_url: "http://localhost:4002"

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true

config :trmnl, renderer_url: "http://localhost:3001", renderer_secret: "development-renderer"
