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

  # redirect root to stac api
  scope "/", StacApiWeb do
    pipe_through :browser
    get "/", RootController, :redirect_to_api
  end

  # STAC API (REST) endpoints - versioned API structure
  scope "/api/stac/v1", StacApiWeb do
    pipe_through :api

    # Root and search endpoints
    get "/", RootController, :index
    get "/search", SearchController, :index
    post "/search", SearchController, :index
    get "/catalog/:id", RootController, :catalog
    get "/openapi.json", RootController, :openapi
    get "/docs", RootController, :docs

    # Legacy collection endpoints (for backward compatibility)
    get "/collections", CollectionsController, :index
    get "/collections/:id", CollectionsController, :show
    get "/collections/:id/items", CollectionsController, :items
    get "/collections/:collection_id/items/:item_id", CollectionsController, :show_item

    # CRUD endpoints for catalogs
    get "/catalogs", CatalogsCrudController, :index
    post "/catalogs", CatalogsCrudController, :create
    get "/catalogs/:id", CatalogsCrudController, :show
    put "/catalogs/:id", CatalogsCrudController, :update
    delete "/catalogs/:id", CatalogsCrudController, :delete

    # CRUD endpoints for collections
    get "/collections", CollectionsCrudController, :index
    post "/collections", CollectionsCrudController, :create
    get "/collections/:id", CollectionsCrudController, :show
    put "/collections/:id", CollectionsCrudController, :update
    delete "/collections/:id", CollectionsCrudController, :delete

    # CRUD endpoints for items
    get "/items", ItemsCrudController, :index
    post "/items", ItemsCrudController, :create
    post "/items/import", ItemsCrudController, :bulk_import
    get "/items/:id", ItemsCrudController, :show
    put "/items/:id", ItemsCrudController, :update
    delete "/items/:id", ItemsCrudController, :delete
  end

  # Web/GUI interface endpoints
  scope "/web", StacApiWeb do
    pipe_through :browser
    get "/browse", StacBrowserController, :index
    get "/browse/*path", StacBrowserController, :show
    get "/search", StacBrowserController, :search
  end

  # Web API endpoints (for AJAX calls from web interface)
  scope "/web", StacApiWeb do
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
