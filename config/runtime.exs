import Config
if System.get_env("PHX_SERVER"), do: config(:trmnl, TrmnlWeb.Endpoint, server: true)

if config_env() == :prod do
  public_url = System.fetch_env!("PUBLIC_URL")
  uri = URI.parse(public_url)
  key = System.fetch_env!("TOKEN_ENCRYPTION_KEY") |> Base.decode64!()
  if byte_size(key) != 32, do: raise("TOKEN_ENCRYPTION_KEY must encode 32 bytes")
  password = System.fetch_env!("ADMIN_PASSWORD")
  if byte_size(password) < 16, do: raise("ADMIN_PASSWORD must have at least 16 bytes")
  config :trmnl, Trmnl.Repo, url: System.fetch_env!("DATABASE_URL"), pool_size: 10

  config :trmnl, TrmnlWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: 4000],
    url: [scheme: uri.scheme, host: uri.host, port: uri.port],
    check_origin: [public_url, System.get_env("GOOGLE_BROWSER_ORIGIN", "http://localhost:4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :trmnl,
    admin_password: password,
    encryption_key: key,
    public_url: String.trim_trailing(public_url, "/"),
    renderer_url: System.get_env("RENDERER_URL", "http://renderer:3001"),
    renderer_secret: System.fetch_env!("RENDERER_SECRET")
end

config :trmnl,
  google_client_id: System.get_env("GOOGLE_CLIENT_ID", ""),
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET", ""),
  google_redirect_uri:
    System.get_env(
      "GOOGLE_REDIRECT_URI",
      "http://localhost:#{if config_env() == :dev, do: System.get_env("PORT", "4000"), else: "4000"}/oauth/callback"
    )

config :trmnl, openrouter_api_key: System.get_env("OPENROUTER_API_KEY", "")
