defmodule StacApiWeb.Router do
  use StacApiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug StacApiWeb.Plugs.AuthPlug
  end

  pipeline :read_auth do
    plug StacApiWeb.Plugs.ReadAuthPlug
  end

  # redirect root to stac api
  scope "/", StacApiWeb do
    pipe_through :browser
    get "/", RootController, :redirect_to_api
  end

  # STAC API (REST) endpoints - versioned API structure
  # Read endpoints use optional read auth to filter private catalogs
  scope "/api/stac/v1", StacApiWeb do
    pipe_through [:api, :read_auth]

    # Root and search endpoints (public read-only)
    get "/", RootController, :index
    get "/search", SearchController, :index
    post "/search", SearchController, :index
    get "/catalog/:id", RootController, :catalog
    get "/openapi.json", RootController, :openapi
    get "/docs", RootController, :docs

    # Legacy collection endpoints (for backward compatibility - read-only)
    get "/collections", CollectionsController, :index
    get "/collections/:id", CollectionsController, :show
    get "/collections/:id/items", CollectionsController, :items
    get "/collections/:collection_id/items/:item_id", CollectionsController, :show_item

    # CRUD endpoints for catalogs (read-only endpoints - public)
    get "/catalogs", CatalogsCrudController, :index
    get "/catalogs/:id", CatalogsCrudController, :show

    # CRUD endpoints for collections (read-only endpoints - public)
    get "/collections", CollectionsCrudController, :index
    get "/collections/:id", CollectionsCrudController, :show

    # CRUD endpoints for items (read-only endpoints - public)
    get "/items", ItemsCrudController, :index
    get "/items/:id", ItemsCrudController, :show
  end

  # Protected write endpoints (require authentication)
  scope "/api/stac/v1", StacApiWeb do
    pipe_through [:api, :auth]

    # Protected write endpoints for catalogs
    post "/catalogs", CatalogsCrudController, :create
    put "/catalogs/:id", CatalogsCrudController, :update
    patch "/catalogs/:id", CatalogsCrudController, :patch
    delete "/catalogs/:id", CatalogsCrudController, :delete

    # Protected write endpoints for collections
    post "/collections", CollectionsCrudController, :create
    put "/collections/:id", CollectionsCrudController, :update
    patch "/collections/:id", CollectionsCrudController, :patch
    delete "/collections/:id", CollectionsCrudController, :delete

    # Protected write endpoints for items
    post "/items", ItemsCrudController, :create
    post "/items/import", ItemsCrudController, :bulk_import
    put "/items/:id", ItemsCrudController, :update
    patch "/items/:id", ItemsCrudController, :patch
    delete "/items/:id", ItemsCrudController, :delete
  end

  # Web/GUI interface endpoints
  scope "/stac/web", StacApiWeb do
    pipe_through :browser
    get "/browse", StacBrowserController, :index
    get "/browse/*path", StacBrowserController, :show
    get "/search", StacBrowserController, :search
  end

  # Web API endpoints (for AJAX calls from web interface)
  scope "/stac/web", StacApiWeb do
    pipe_through :api
    get "/search/api", StacBrowserController, :search_api
  end


  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:stac_api, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: StacApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
