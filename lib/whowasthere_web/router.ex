defmodule WhoWasThereWeb.Router do
  use WhoWasThereWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WhoWasThereWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :site do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :put_secure_browser_headers
  end

  pipeline :ingest do
    plug WhoWasThereWeb.Plugs.CORS
  end

  scope "/", WhoWasThereWeb do
    pipe_through :ingest

    get "/w.js", IngestController, :asset
    post "/w.js", IngestController, :event
    options "/w.js", IngestController, :event
    post "/e", IngestController, :event
    options "/e", IngestController, :event
    get "/e.gif", IngestController, :pixel
    get "/t.js", IngestController, :script
    get "/health", SiteController, :health
  end

  scope "/", WhoWasThereWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/LICENSE", PageController, :license
    live "/d/:token", DashLive
  end

  scope "/", WhoWasThereWeb do
    pipe_through :site

    get "/new", SiteController, :create
    get "/pay", SiteController, :pay
    get "/renew", SiteController, :renew
    get "/notify", SiteController, :notify
  end
end
