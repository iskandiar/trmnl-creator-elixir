defmodule TrmnlWeb.Router do
  use TrmnlWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TrmnlWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug TrmnlWeb.Auth
  end

  scope "/", TrmnlWeb do
    get "/health", HealthController, :show
    get "/api/setup", DeviceController, :setup
    get "/api/display", DeviceController, :display
    post "/api/log", DeviceController, :log
    get "/api/image", DeviceController, :image
    get "/api/setup-image.bmp", DeviceController, :setup_image
  end

  scope "/", TrmnlWeb do
    pipe_through :browser
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", TrmnlWeb do
    pipe_through [:browser, :admin]
    get "/oauth/start", OAuthController, :start
    get "/oauth/callback", OAuthController, :callback

    live_session :admin, on_mount: [{TrmnlWeb.Auth, :admin}] do
      live "/", DashboardLive
    end
  end
end
