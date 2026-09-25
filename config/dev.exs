import Config

config :trmnl, Trmnl.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 55432,
  database: "trmnl_dev",
  pool_size: 10

config :trmnl, TrmnlWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("development-only-", 4)

config :trmnl,
  admin_password: "development-password",
  encryption_key: :crypto.hash(:sha256, "development-only"),
  renderer_url: "http://localhost:3001",
  renderer_secret: "development-renderer",
  public_url: "http://localhost:#{System.get_env("PORT", "4000")}"

config :logger, level: :info
