defmodule StacApiWeb.RootController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.{Collection, Catalog}
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  @conformance_classes [
    "https://api.stacspec.org/v1.0.0/core",
    "https://api.stacspec.org/v1.0.0/item-search",
    "https://api.stacspec.org/v1.0.0/item-search#context",
    "https://api.stacspec.org/v1.0.0/ogcapi-features",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/core",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/oas30",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/geojson"
  ]

  def redirect_to_landing(conn, _params) do
    redirect(conn, to: "/stac/web/")
  end

  def conformance(conn, _params) do
    json(conn, %{conformsTo: @conformance_classes})
  end

  def index(conn, _params) do
    authenticated = conn.assigns[:authenticated] || false

    sub_catalogs_query = if authenticated do
      from c in Catalog,
        where: c.depth == 0 and c.id != "pygeoapi-stac",
        order_by: [asc: c.id]
    else
      from c in Catalog,
        where: c.depth == 0 and c.id != "pygeoapi-stac" and (c.private == false or is_nil(c.private)),
        order_by: [asc: c.id]
    end

    sub_catalogs = Repo.all(sub_catalogs_query)

    root_collections = Repo.all(from c in Collection,
      where: is_nil(c.catalog_id),
      order_by: [asc: c.id]
    )

    sub_catalog_child_links = Enum.map(sub_catalogs, fn catalog ->
      LinkResolver.create_link("child", "/stac/api/v1/catalog/#{catalog.id}",
        title: catalog.title || catalog.id
      )
    end)

    root_collection_child_links = Enum.map(root_collections, fn collection ->
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
      conformsTo: @conformance_classes,
      links: [
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
        LinkResolver.create_link("data", "/stac/api/v1/collections",
          title: "Collections"
        ),
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
          child_catalogs_query = if authenticated do
            from c in Catalog,
              where: c.parent_catalog_id == ^catalog_id,
              order_by: [asc: c.id]
          else
            from c in Catalog,
              where: c.parent_catalog_id == ^catalog_id and (c.private == false or is_nil(c.private)),
              order_by: [asc: c.id]
          end

          child_catalogs = Repo.all(child_catalogs_query)

          collections_query = if authenticated do
            from c in Collection,
              where: c.catalog_id == ^catalog_id,
              order_by: [asc: c.id]
          else
            from c in Collection,
              left_join: cat in Catalog, on: c.catalog_id == cat.id,
              where: c.catalog_id == ^catalog_id and (is_nil(cat.private) or cat.private != true),
              order_by: [asc: c.id]
          end

          collections = Repo.all(collections_query)

        catalog_child_links = Enum.map(child_catalogs, fn child ->
          LinkResolver.create_link("child", "/stac/api/v1/catalog/#{child.id}",
            title: child.title || child.id
          )
        end)

        collection_child_links = Enum.map(collections, fn collection ->
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
          links: [
            LinkResolver.create_link("root", "/stac/api/v1/"),
            LinkResolver.create_link("self", "/stac/api/v1/catalog/#{catalog.id}")
          ] ++ catalog_child_links ++ collection_child_links
        }

        # Add parent link for sub-catalogs
        # Depth 0 catalogs (except root) should link to root, deeper catalogs link to their parent
        parent_link = case catalog.parent_catalog_id do
          nil when catalog.id != "pygeoapi-stac" ->
            # Top-level sub-catalog links to root
            LinkResolver.create_link("parent", "/stac/api/v1/")
          parent_id when is_binary(parent_id) ->
            # Sub-catalog links to parent catalog
            LinkResolver.create_link("parent", "/stac/api/v1/catalog/#{parent_id}")
          _ ->
            nil
        end

        catalog_response = if parent_link do
          Map.put(catalog_response, :links, [parent_link | catalog_response.links])
        else
          catalog_response
        end

          json(conn, catalog_response)
        end
    end
  end

  def openapi(conn, _params) do
    openapi_spec = %{
      openapi: "3.0.3",
      info: %{
        title: "Geokuup STAC API",
        description: "SpatioTemporal Asset Catalog API for geospatial data discovery and access",
        version: "1.0.0",
        contact: %{
          name: "Landscape Geoinformatics Lab"
        }
      },
      servers: [
        %{
          url: "/stac/api/v1",
          description: "STAC API v1"
        }
      ],
      paths: %{
        "/" => %{
          get: %{
            summary: "Landing page",
            description: "The landing page provides links to the API capabilities",
            responses: %{
              "200" => %{
                description: "The landing page",
                content: %{
                  "application/json" => %{
                    schema: %{
                      "$ref" => "#/components/schemas/Catalog"
                    }
                  }
                }
              }
            }
          }
        },
        "/collections" => %{
          get: %{
            summary: "List collections",
            description: "List all collections",
            responses: %{
              "200" => %{
                description: "A list of collections",
                content: %{
                  "application/json" => %{
                    schema: %{
                      type: "object",
                      properties: %{
                        collections: %{
                          type: "array",
                          items: %{
                            "$ref" => "#/components/schemas/Collection"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/search" => %{
          get: %{
            summary: "Search items",
            description: "Search for STAC items",
            responses: %{
              "200" => %{
                description: "A GeoJSON FeatureCollection",
                content: %{
                  "application/geo+json" => %{
                    schema: %{
                      "$ref" => "#/components/schemas/FeatureCollection"
                    }
                  }
                }
              }
            }
          }
        }
      },
      components: %{
        schemas: %{
          Catalog: %{
            type: "object",
            required: ["stac_version", "id", "type", "links"],
            properties: %{
              stac_version: %{type: "string"},
              id: %{type: "string"},
              title: %{type: "string"},
              description: %{type: "string"},
              type: %{type: "string", enum: ["Catalog"]},
              conformsTo: %{
                type: "array",
                items: %{type: "string"}
              },
              links: %{
                type: "array",
                items: %{"$ref" => "#/components/schemas/Link"}
              }
            }
          },
          Collection: %{
            type: "object",
            required: ["stac_version", "id", "type", "links"],
            properties: %{
              stac_version: %{type: "string"},
              id: %{type: "string"},
              title: %{type: "string"},
              description: %{type: "string"},
              type: %{type: "string", enum: ["Collection"]},
              license: %{type: "string"},
              extent: %{type: "object"},
              links: %{
                type: "array",
                items: %{"$ref" => "#/components/schemas/Link"}
              }
            }
          },
          FeatureCollection: %{
            type: "object",
            required: ["type", "features"],
            properties: %{
              type: %{type: "string", enum: ["FeatureCollection"]},
              features: %{
                type: "array",
                items: %{"$ref" => "#/components/schemas/Feature"}
              }
            }
          },
          Feature: %{
            type: "object",
            required: ["type", "id", "geometry", "properties"],
            properties: %{
              type: %{type: "string", enum: ["Feature"]},
              id: %{type: "string"},
              geometry: %{type: "object"},
              properties: %{type: "object"},
              bbox: %{type: "array"},
              assets: %{type: "object"}
            }
          },
          Link: %{
            type: "object",
            required: ["rel", "href"],
            properties: %{
              rel: %{type: "string"},
              href: %{type: "string"},
              type: %{type: "string"},
              title: %{type: "string"},
              method: %{type: "string"}
            }
          }
        }
      }
    }

    conn
    |> put_resp_content_type("application/vnd.oai.openapi+json;version=3.0")
    |> json(openapi_spec)
  end

  def docs(conn, _params) do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Geokuup STAC API Documentation</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .header { border-bottom: 2px solid #333; padding-bottom: 20px; }
            .endpoint { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
            .method { font-weight: bold; color: #0066cc; }
            .path { font-family: monospace; background: #f5f5f5; padding: 2px 5px; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Geokuup STAC API Documentation</h1>
            <p>SpatioTemporal Asset Catalog API for geospatial data discovery and access</p>
        </div>

        <h2>API Endpoints</h2>

        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/stac/api/v1/</div>
            <p><strong>Landing Page</strong> - Provides links to API capabilities and collections</p>
        </div>

        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/stac/api/v1/collections</div>
            <p><strong>List Collections</strong> - Returns all available collections</p>
        </div>

        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/stac/api/v1/collections/{collection_id}</div>
            <p><strong>Get Collection</strong> - Returns details for a specific collection</p>
        </div>

        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/stac/api/v1/search</div>
            <p><strong>Search Items</strong> - Search for STAC items with various filters</p>
        </div>

        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/stac/web/browse</div>
            <p><strong>Web Interface</strong> - HTML browser interface for exploring data</p>
        </div>

        <h2>STAC Compliance</h2>
        <p>This API implements the <a href="https://api.stacspec.org/v1.0.0/core">STAC API - Core</a> specification.</p>

        <h2>OpenAPI Specification</h2>
        <p><a href="/stac/api/v1/openapi.json">Download OpenAPI 3.0 specification</a></p>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
