# lib/stac_api_web/controllers/root_controller.ex
defmodule StacApiWeb.RootController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.Collection
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  def redirect_to_api(conn, _params) do
    redirect(conn, to: "/api/stac/v1/")
  end

  def index(conn, _params) do
    # Get collections for child links
    collections = Repo.all(from c in Collection, limit: 20, order_by: [asc: c.id])
    
    # Build child links from collections
    child_links = Enum.map(collections, fn collection ->
      LinkResolver.create_link("child", "/api/stac/v1/collections/#{collection.id}",
        title: collection.title || collection.id
      )
    end)

    # STAC Core compliant landing page
    json(conn, %{
      stac_version: "1.0.0",
      id: "aoraki-stac-api",
      title: "Aoraki STAC API",
      description: "SpatioTemporal Asset Catalog API for geospatial data discovery and access",
      type: "Catalog",
      conformsTo: [
        "https://api.stacspec.org/v1.0.0/core",
        "https://api.stacspec.org/v1.0.0/item-search"
      ],
      links: [
        # Required STAC Core links
        LinkResolver.create_link("self", "/api/stac/v1/"),
        LinkResolver.create_link("root", "/api/stac/v1/"),
        LinkResolver.create_link("service-desc", "/api/stac/v1/openapi.json",
          type: "application/vnd.oai.openapi+json;version=3.0",
          title: "OpenAPI service description"
        ),
        LinkResolver.create_link("service-doc", "/api/stac/v1/docs",
          type: "text/html",
          title: "OpenAPI service documentation"
        ),
        LinkResolver.create_link("data", "/api/stac/v1/collections",
          title: "Collections"
        ),
        LinkResolver.create_link("search", "/api/stac/v1/search",
          type: "application/geo+json",
          title: "STAC search",
          method: "GET"
        ),
        LinkResolver.create_link("search", "/api/stac/v1/search",
          type: "application/geo+json",
          title: "STAC search",
          method: "POST"
        ),
        # Custom web interface link
        LinkResolver.create_link("browser", "/web/browse",
          type: "text/html",
          title: "Web Browser Interface"
        )
      ] ++ child_links,
      stac_extensions: []
    })
  end

  def openapi(conn, _params) do
    openapi_spec = %{
      openapi: "3.0.3",
      info: %{
        title: "Aoraki STAC API",
        description: "SpatioTemporal Asset Catalog API for geospatial data discovery and access",
        version: "1.0.0",
        contact: %{
          name: "Aoraki Portal Team"
        }
      },
      servers: [
        %{
          url: "/api/stac/v1",
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
        <title>Aoraki STAC API Documentation</title>
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
            <h1>Aoraki STAC API Documentation</h1>
            <p>SpatioTemporal Asset Catalog API for geospatial data discovery and access</p>
        </div>
        
        <h2>API Endpoints</h2>
        
        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/api/stac/v1/</div>
            <p><strong>Landing Page</strong> - Provides links to API capabilities and collections</p>
        </div>
        
        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/api/stac/v1/collections</div>
            <p><strong>List Collections</strong> - Returns all available collections</p>
        </div>
        
        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/api/stac/v1/collections/{collection_id}</div>
            <p><strong>Get Collection</strong> - Returns details for a specific collection</p>
        </div>
        
        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/api/stac/v1/search</div>
            <p><strong>Search Items</strong> - Search for STAC items with various filters</p>
        </div>
        
        <div class="endpoint">
            <div class="method">GET</div>
            <div class="path">/web/browse</div>
            <p><strong>Web Interface</strong> - HTML browser interface for exploring data</p>
        </div>
        
        <h2>STAC Compliance</h2>
        <p>This API implements the <a href="https://api.stacspec.org/v1.0.0/core">STAC API - Core</a> specification.</p>
        
        <h2>OpenAPI Specification</h2>
        <p><a href="/api/stac/v1/openapi.json">Download OpenAPI 3.0 specification</a></p>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
