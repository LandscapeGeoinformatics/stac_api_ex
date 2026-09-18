defmodule StacApiWeb.RootController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.{Collection, Catalog}
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  alias StacApiWeb.ApiDocs

  # Conformance classes live in ApiDocs so the landing page, the conformance
  # endpoint, openapi.json and the docs page all report the same list.
  defp conformance_classes, do: ApiDocs.conformance_classes()

  def redirect_to_landing(conn, _params) do
    redirect(conn, to: "/stac/web/")
  end

  def conformance(conn, _params) do
    json(conn, %{conformsTo: conformance_classes()})
  end

  def index(conn, _params) do
    authenticated = conn.assigns[:authenticated] || false

    sub_catalogs_query =
      if authenticated do
        from(c in Catalog,
          where: c.depth == 0 and c.id != "pygeoapi-stac",
          order_by: [asc: c.id]
        )
      else
        from(c in Catalog,
          where:
            c.depth == 0 and c.id != "pygeoapi-stac" and (c.private == false or is_nil(c.private)),
          order_by: [asc: c.id]
        )
      end

    sub_catalogs = Repo.all(sub_catalogs_query)

    root_collections =
      Repo.all(
        from(c in Collection,
          where: is_nil(c.catalog_id),
          order_by: [asc: c.id]
        )
      )

    sub_catalog_child_links =
      Enum.map(sub_catalogs, fn catalog ->
        LinkResolver.create_link("child", "/stac/api/v1/catalog/#{catalog.id}",
          title: catalog.title || catalog.id
        )
      end)

    root_collection_child_links =
      Enum.map(root_collections, fn collection ->
        LinkResolver.create_link("child", "/stac/api/v1/collections/#{collection.id}",
          title: collection.title || collection.id
        )
      end)

    # STAC Core compliant landing page
    json(conn, %{
      stac_version: "1.0.0",
      id: "geokuup-stac-api",
      title: "Geokuup STAC API",
      description: "SpatioTemporal Asset Catalog API for geospatial data discovery and access",
      type: "Catalog",
      conformsTo: conformance_classes(),
      links:
        [
          # Required STAC Core links
          LinkResolver.create_link("self", "/stac/api/v1/"),
          LinkResolver.create_link("root", "/stac/api/v1/"),
          LinkResolver.create_link("conformance", "/stac/api/v1/conformance",
            title: "OGC API conformance classes implemented by this server"
          ),
          LinkResolver.create_link("service-desc", "/stac/api/v1/openapi.json",
            type: "application/vnd.oai.openapi+json;version=3.0",
            title: "OpenAPI service description"
          ),
          LinkResolver.create_link("service-doc", "/stac/api/v1/docs",
            type: "text/html",
            title: "OpenAPI service documentation"
          ),
          LinkResolver.create_link("data", "/stac/api/v1/collections", title: "Collections"),
          # GET search: type = response media type
          LinkResolver.create_link("search", "/stac/api/v1/search",
            type: "application/geo+json",
            title: "STAC search",
            method: "GET"
          ),
          # POST search: type = request body media type (clients set Content-Type from this)
          LinkResolver.create_link("search", "/stac/api/v1/search",
            type: "application/json",
            title: "STAC search",
            method: "POST"
          ),
          LinkResolver.create_link("browser", "/stac/web/browse",
            type: "text/html",
            title: "Web Browser Interface"
          )
        ] ++ sub_catalog_child_links ++ root_collection_child_links,
      stac_extensions: []
    })
  end

  def catalog(conn, %{"id" => catalog_id}) do
    authenticated = conn.assigns[:authenticated] || false

    case Repo.get(Catalog, catalog_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Catalog not found"})

      catalog ->
        catalog_private = catalog.private == true

        if catalog_private && !authenticated do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Catalog not found"})
        else
          child_catalogs_query =
            if authenticated do
              from(c in Catalog,
                where: c.parent_catalog_id == ^catalog_id,
                order_by: [asc: c.id]
              )
            else
              from(c in Catalog,
                where:
                  c.parent_catalog_id == ^catalog_id and (c.private == false or is_nil(c.private)),
                order_by: [asc: c.id]
              )
            end

          child_catalogs = Repo.all(child_catalogs_query)

          collections_query =
            if authenticated do
              from(c in Collection,
                where: c.catalog_id == ^catalog_id,
                order_by: [asc: c.id]
              )
            else
              from(c in Collection,
                left_join: cat in Catalog,
                on: c.catalog_id == cat.id,
                where:
                  c.catalog_id == ^catalog_id and (is_nil(cat.private) or cat.private != true),
                order_by: [asc: c.id]
              )
            end

          collections = Repo.all(collections_query)

          catalog_child_links =
            Enum.map(child_catalogs, fn child ->
              LinkResolver.create_link("child", "/stac/api/v1/catalog/#{child.id}",
                title: child.title || child.id
              )
            end)

          collection_child_links =
            Enum.map(collections, fn collection ->
              LinkResolver.create_link("child", "/stac/api/v1/collections/#{collection.id}",
                title: collection.title || collection.id
              )
            end)

          catalog_response = %{
            stac_version: catalog.stac_version || "1.0.0",
            type: "Catalog",
            id: catalog.id,
            title: catalog.title,
            description: catalog.description,
            extent: catalog.extent,
            links:
              [
                LinkResolver.create_link("root", "/stac/api/v1/"),
                LinkResolver.create_link("self", "/stac/api/v1/catalog/#{catalog.id}")
              ] ++ catalog_child_links ++ collection_child_links
          }

          # Add parent link for sub-catalogs
          # Depth 0 catalogs (except root) should link to root, deeper catalogs link to their parent
          parent_link =
            case catalog.parent_catalog_id do
              nil when catalog.id != "pygeoapi-stac" ->
                # Top-level sub-catalog links to root
                LinkResolver.create_link("parent", "/stac/api/v1/")

              parent_id when is_binary(parent_id) ->
                # Sub-catalog links to parent catalog
                LinkResolver.create_link("parent", "/stac/api/v1/catalog/#{parent_id}")

              _ ->
                nil
            end

          catalog_response =
            if parent_link do
              Map.put(catalog_response, :links, [parent_link | catalog_response.links])
            else
              catalog_response
            end

          json(conn, catalog_response)
        end
    end
  end

  # The Management API is only described to callers that proved read-write
  # access: an RW X-API-Key header, or a browser session unlocked with an RW key
  # (the lock icon). Everyone else gets a read-only view that does not mention
  # write endpoints at all.
  def openapi(conn, _params) do
    include_management =
      conn.assigns[:auth_level] == :read_write or
        get_session(conn, :browse_auth_level) == :read_write

    conn
    |> put_resp_content_type("application/vnd.oai.openapi+json;version=3.0")
    |> json(ApiDocs.openapi_spec(ApiDocs.base_url(), include_management: include_management))
  end

  def docs(conn, _params) do
    base_url = ApiDocs.base_url()
    browse_authenticated = get_session(conn, :browse_authenticated) == true

    show_management =
      browse_authenticated and get_session(conn, :browse_auth_level) == :read_write

    quickstart =
      ApiDocs.find_endpoint("search-get")
      |> ApiDocs.curl_example(base_url)

    conn
    |> assign(:page_title, "#{ApiDocs.title()} – Documentation")
    |> assign(:base_url, base_url)
    |> assign(:browse_authenticated, browse_authenticated)
    |> assign(:show_management, show_management)
    |> assign(
      :auth_levels,
      if(show_management, do: [:public, :optional, :rw], else: [:public, :optional])
    )
    |> assign(:groups, ApiDocs.groups(include_management: show_management))
    |> assign(:conformance, ApiDocs.conformance_classes())
    |> assign(:quickstart, quickstart)
    |> render(:docs)
  end
end
