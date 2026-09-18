defmodule StacApiWeb.ApiDocs do
  @moduledoc """
  Single source of truth for the HTTP API documentation.

  `groups/0` describes every route the application serves. Both the HTML
  documentation page (`GET /stac/api/v1/docs`) and the OpenAPI 3.0 document
  (`GET /stac/api/v1/openapi.json`) are generated from it, so the two cannot
  drift apart. Add or change an endpoint here and both views follow.

  Each endpoint map has:

    * `id` – anchor / operationId
    * `method`, `path` – path uses OpenAPI `{param}` placeholders
    * `summary`, `description`
    * `auth` – `:public`, `:optional` (X-API-Key unlocks private catalogs) or
      `:rw` (read-write key required, 401 otherwise)
    * `params` – list of `%{name, in, type, required, description, example}`
    * `request_body` – `%{description, schema, example}` or nil
    * `responses` – list of `%{status, media, description, schema}`
    * `example_query` – query string appended to the example request
  """

  @conformance_classes [
    "https://api.stacspec.org/v1.0.0/core",
    "https://api.stacspec.org/v1.0.0/item-search",
    "https://api.stacspec.org/v1.0.0/item-search#context",
    "https://api.stacspec.org/v1.0.0/ogcapi-features",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/core",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/oas30",
    "http://www.opengis.net/spec/ogcapi-features-1/1.0/conf/geojson"
  ]

  @stac_version "1.0.0"
  @openapi_version "3.0.3"
  @title "Geokuup STAC API"
  @description "SpatioTemporal Asset Catalog API for geospatial data discovery and access"

  def conformance_classes, do: @conformance_classes
  def stac_version, do: @stac_version
  def openapi_version, do: @openapi_version
  def title, do: @title
  def description, do: @description

  def app_version do
    case Application.spec(:stac_api, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  @doc "Absolute base URL of this deployment, without trailing slash."
  def base_url do
    case Application.get_env(:stac_api, :base_url) do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
      _ -> StacApiWeb.Endpoint.url()
    end
  end

  @doc "Human readable description of each conformance class URI."
  def conformance_label(uri) do
    cond do
      String.contains?(uri, "stacspec.org") and String.ends_with?(uri, "/core") ->
        "STAC API – Core"

      String.contains?(uri, "item-search#context") ->
        "STAC API – Item Search: Context extension"

      String.contains?(uri, "item-search") ->
        "STAC API – Item Search"

      String.contains?(uri, "stacspec.org") and String.contains?(uri, "ogcapi-features") ->
        "STAC API – Features"

      String.contains?(uri, "ogcapi-features-1/1.0/conf/core") ->
        "OGC API – Features Part 1: Core"

      String.contains?(uri, "conf/oas30") ->
        "OGC API – Features: OpenAPI 3.0"

      String.contains?(uri, "conf/geojson") ->
        "OGC API – Features: GeoJSON"

      true ->
        uri
    end
  end

  # ---------------------------------------------------------------------------
  # Endpoint catalogue
  # ---------------------------------------------------------------------------

  @doc """
  Endpoint groups for display. The Management API group is only included with
  `include_management: true`, i.e. for callers that proved read-write access;
  everyone else must not even learn that write endpoints exist.
  """
  def groups(opts \\ []) do
    include_management = Keyword.get(opts, :include_management, false)

    Enum.reject(all_groups(), fn g -> g.id == "management-api" and not include_management end)
  end

  defp all_groups do
    [
      %{
        id: "stac-api",
        tag: "STAC API",
        title: "STAC API v1 (read)",
        base: "/stac/api/v1",
        description:
          "OGC API – Features / STAC 1.0.0 conformant read endpoints. Public without a key; " <>
            "an optional X-API-Key additionally exposes private catalogs.",
        endpoints: stac_api_endpoints()
      },
      %{
        id: "management-api",
        tag: "Management API",
        title: "Management API v1 (read-write)",
        base: "/stac/manage/v1",
        description:
          "Administrative CRUD for catalogs, collections and items. Every request needs a " <>
            "read-write X-API-Key; missing or read-only keys get 401. Not part of the STAC spec.",
        endpoints: management_endpoints()
      },
      %{
        id: "web",
        tag: "Web interface",
        title: "Web interface",
        base: "/stac/web",
        description:
          "Human-facing HTML pages. Private catalogs can be unlocked in the browser with an API key " <>
            "(session cookie), independent of the X-API-Key header.",
        endpoints: web_endpoints()
      }
    ]
  end

  @doc "All endpoints flattened, each with its group tag. Same `opts` as `groups/1`."
  def endpoints(opts \\ []) do
    Enum.flat_map(groups(opts), fn g -> Enum.map(g.endpoints, &Map.put(&1, :tag, g.tag)) end)
  end

  def find_endpoint(id), do: Enum.find(endpoints(include_management: true), &(&1.id == id))

  # --- shared parameter definitions -----------------------------------------

  defp query(name, type, description, opts) do
    %{
      name: name,
      in: :query,
      type: type,
      required: Keyword.get(opts, :required, false),
      description: description,
      example: Keyword.get(opts, :example)
    }
  end

  defp path_param(name, description, example) do
    %{
      name: name,
      in: :path,
      type: "string",
      required: true,
      description: description,
      example: example
    }
  end

  defp limit_param(default, max) do
    query(
      "limit",
      "integer",
      "Page size. Default #{default}, values above #{max} are capped.",
      example: "5"
    )
  end

  defp offset_param,
    do: query("offset", "integer", "Number of results to skip (default 0).", example: "0")

  defp search_params(:get) do
    [
      query("collections", "string", "Comma-separated collection ids to search in.",
        example: "estonia-soil"
      ),
      query("ids", "string", "Comma-separated item ids.", example: "dem_10m_clipped"),
      query(
        "bbox",
        "string",
        "Bounding box west,south,east,north in WGS 84 (4 numbers, or 6 with elevation).",
        example: "21.6,57.4,28.3,59.9"
      ),
      query(
        "datetime",
        "string",
        "RFC 3339 instant (2020-01-01T00:00:00Z) or interval start/end. Either end may be open with '..'. " <>
          "Items whose datetime, or start/end range, overlaps the interval match. Unparseable values return 400.",
        example: "2020-01-01T00:00:00Z/2021-12-31T23:59:59Z"
      ),
      query(
        "intersects",
        "string",
        "URL-encoded GeoJSON geometry; only items whose footprint intersects it are returned.",
        example: nil
      ),
      limit_param(10, 100),
      offset_param()
    ]
  end

  defp search_body do
    %{
      description:
        "Same filters as the GET form, as a JSON object. Arrays replace comma-separated strings and " <>
          "intersects is a GeoJSON geometry object.",
      schema: "SearchBody",
      example: %{
        "collections" => ["estonia-sentinel2-ndvi"],
        "bbox" => [21.6, 57.4, 28.3, 59.9],
        "datetime" => "2020-04-01T00:00:00Z/2020-10-31T23:59:59Z",
        "limit" => 5
      }
    }
  end

  defp ok(media, description, schema),
    do: %{status: 200, media: media, description: description, schema: schema}

  defp created(description, schema),
    do: %{status: 201, media: "application/json", description: description, schema: schema}

  defp err(status, description),
    do: %{status: status, media: "application/json", description: description, schema: "Error"}

  @json "application/json"
  @geojson "application/geo+json"
  @html "text/html"

  # --- STAC API ----------------------------------------------------------------

  defp stac_api_endpoints do
    [
      %{
        id: "landing",
        method: "GET",
        path: "/stac/api/v1/",
        summary: "Landing page",
        description:
          "Root STAC Catalog with the conformance classes and links to collections, search, the " <>
            "OpenAPI document and every top-level catalog visible to the caller.",
        auth: :optional,
        params: [],
        request_body: nil,
        responses: [ok(@json, "Root catalog", "Catalog")]
      },
      %{
        id: "conformance",
        method: "GET",
        path: "/stac/api/v1/conformance",
        summary: "Conformance classes",
        description:
          "Lists the STAC API and OGC API – Features conformance classes this server implements.",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [ok(@json, "Conformance declaration", "Conformance")]
      },
      %{
        id: "catalog",
        method: "GET",
        path: "/stac/api/v1/catalog/{catalog_id}",
        summary: "Sub-catalog",
        description:
          "A nested catalog with child links to its sub-catalogs and collections. Private catalogs " <>
            "answer 404 unless a valid key is supplied.",
        auth: :optional,
        params: [path_param("catalog_id", "Catalog identifier", "estonia")],
        request_body: nil,
        responses: [ok(@json, "Catalog", "Catalog"), err(404, "Catalog not found or private")]
      },
      %{
        id: "collections",
        method: "GET",
        path: "/stac/api/v1/collections",
        summary: "List collections",
        description:
          "All collections visible to the caller, each with its extent, license, providers and links.",
        auth: :optional,
        params: [],
        request_body: nil,
        responses: [ok(@json, "Collection list", "CollectionList")]
      },
      %{
        id: "collection",
        method: "GET",
        path: "/stac/api/v1/collections/{collection_id}",
        summary: "Get collection",
        description: "A single STAC Collection.",
        auth: :optional,
        params: [path_param("collection_id", "Collection identifier", "estonia-soil")],
        request_body: nil,
        responses: [ok(@json, "Collection", "Collection"), err(404, "Collection not found")]
      },
      %{
        id: "collection-items",
        method: "GET",
        path: "/stac/api/v1/collections/{collection_id}/items",
        summary: "List items of a collection",
        description:
          "OGC API – Features items endpoint. Returns a GeoJSON FeatureCollection ordered by datetime, " <>
            "with self / next / prev pagination links and a context block.",
        auth: :optional,
        params: [
          path_param("collection_id", "Collection identifier", "estonia-soil"),
          limit_param(10, 10_000),
          offset_param()
        ],
        request_body: nil,
        example_query: "limit=2",
        responses: [
          ok(@geojson, "Item collection", "ItemCollection"),
          err(404, "Collection not found")
        ]
      },
      %{
        id: "collection-item",
        method: "GET",
        path: "/stac/api/v1/collections/{collection_id}/items/{item_id}",
        summary: "Get item",
        description: "A single STAC Item (GeoJSON Feature) with its assets and links.",
        auth: :optional,
        params: [
          path_param("collection_id", "Collection identifier", "estonia-topo-10m"),
          path_param("item_id", "Item identifier", "dem_10m_clipped")
        ],
        request_body: nil,
        responses: [ok(@geojson, "Item", "Item"), err(404, "Item not found")]
      },
      %{
        id: "search-get",
        method: "GET",
        path: "/stac/api/v1/search",
        summary: "Search items (GET)",
        description:
          "STAC Item Search across all visible collections. Filters combine with AND. " <>
            "The response context reports returned / matched / limit.",
        auth: :optional,
        params: search_params(:get),
        request_body: nil,
        example_query:
          "collections=estonia-sentinel2-ndvi&datetime=2020-04-01T00:00:00Z/2020-10-31T23:59:59Z&limit=5",
        responses: [
          ok(@geojson, "Matching items", "ItemCollection"),
          err(400, "Invalid datetime parameter")
        ]
      },
      %{
        id: "search-post",
        method: "POST",
        path: "/stac/api/v1/search",
        summary: "Search items (POST)",
        description:
          "Same as the GET search with the filters in a JSON body. Use this form for GeoJSON " <>
            "intersects geometries and long id lists.",
        auth: :optional,
        params: [],
        request_body: search_body(),
        responses: [
          ok(@geojson, "Matching items", "ItemCollection"),
          err(400, "Invalid datetime parameter")
        ]
      },
      %{
        id: "openapi",
        method: "GET",
        path: "/stac/api/v1/openapi.json",
        summary: "OpenAPI document",
        description: "This API described as OpenAPI 3.0 (service-desc link on the landing page).",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [
          %{
            status: 200,
            media: "application/vnd.oai.openapi+json;version=3.0",
            description: "OpenAPI 3.0.3 document",
            schema: nil
          }
        ]
      },
      %{
        id: "docs",
        method: "GET",
        path: "/stac/api/v1/docs",
        summary: "API documentation",
        description: "This page (service-doc link on the landing page).",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [%{status: 200, media: @html, description: "HTML documentation", schema: nil}]
      }
    ]
  end

  # --- Management API ------------------------------------------------------------

  defp management_endpoints do
    catalog_example = %{
      "id" => "my-catalog",
      "title" => "My Catalog",
      "description" => "Example sub-catalog",
      "parent_catalog_id" => "estonia",
      "private" => false
    }

    collection_example = %{
      "id" => "my-collection",
      "type" => "Collection",
      "stac_version" => "1.0.0",
      "title" => "My Collection",
      "description" => "Example collection",
      "license" => "CC-BY-4.0",
      "catalog_id" => "estonia",
      "extent" => %{
        "spatial" => %{"bbox" => [[21.6, 57.4, 28.3, 59.9]]},
        "temporal" => %{"interval" => [["2020-01-01T00:00:00Z", nil]]}
      }
    }

    item_example = %{
      "type" => "Feature",
      "stac_version" => "1.0.0",
      "id" => "my-item",
      "collection" => "my-collection",
      "geometry" => %{
        "type" => "Polygon",
        "coordinates" => [[[21.6, 57.4], [28.3, 57.4], [28.3, 59.9], [21.6, 59.9], [21.6, 57.4]]]
      },
      "bbox" => [21.6, 57.4, 28.3, 59.9],
      "properties" => %{
        "datetime" => nil,
        "start_datetime" => "2020-04-01T00:00:00Z",
        "end_datetime" => "2020-05-31T23:59:59Z",
        "proj:code" => "EPSG:3301"
      },
      "assets" => %{
        "data" => %{
          "href" => "https://example.org/my-item.tif",
          "type" => "image/tiff; application=geotiff; profile=cloud-optimized",
          "roles" => ["data"]
        }
      }
    }

    crud("catalogs", "catalog", "Catalog", "CatalogList", catalog_example, "estonia") ++
      crud(
        "collections",
        "collection",
        "Collection",
        "CollectionList",
        collection_example,
        "estonia-soil"
      ) ++
      items_crud(item_example)
  end

  defp crud(plural, singular, schema, list_schema, example, example_id) do
    base = "/stac/manage/v1/#{plural}"

    id_param =
      path_param("#{singular}_id", "#{String.capitalize(singular)} identifier", example_id)

    write_errors = [
      err(400, "Malformed body"),
      err(401, "Missing or non-RW key"),
      err(422, "Validation failed")
    ]

    [
      %{
        id: "manage-#{plural}-list",
        method: "GET",
        path: base,
        summary: "List #{plural}",
        description: "All #{plural} including private ones.",
        auth: :rw,
        params: [],
        request_body: nil,
        responses: [
          ok(@json, "#{String.capitalize(plural)} list", list_schema),
          err(401, "Missing or non-RW key")
        ]
      },
      %{
        id: "manage-#{plural}-show",
        method: "GET",
        path: "#{base}/{#{singular}_id}",
        summary: "Get #{singular}",
        description: "A single #{singular} with generated links.",
        auth: :rw,
        params: [id_param],
        request_body: nil,
        responses: [
          ok(@json, String.capitalize(singular), schema),
          err(401, "Missing or non-RW key"),
          err(404, "Not found")
        ]
      },
      %{
        id: "manage-#{plural}-create",
        method: "POST",
        path: base,
        summary: "Create #{singular}",
        description: "Creates a #{singular}. The id must be unique; an existing id answers 409.",
        auth: :rw,
        params: [],
        request_body: %{
          description: "#{String.capitalize(singular)} to create",
          schema: schema,
          example: example
        },
        responses:
          [created("Created #{singular}", schema)] ++
            write_errors ++ [err(409, "Id already exists")]
      },
      %{
        id: "manage-#{plural}-update",
        method: "PUT",
        path: "#{base}/{#{singular}_id}",
        summary: "Replace #{singular}",
        description: "Full replacement of the #{singular}.",
        auth: :rw,
        params: [id_param],
        request_body: %{description: "Complete #{singular}", schema: schema, example: example},
        responses:
          [ok(@json, "Updated #{singular}", schema)] ++ write_errors ++ [err(404, "Not found")]
      },
      %{
        id: "manage-#{plural}-patch",
        method: "PATCH",
        path: "#{base}/{#{singular}_id}",
        summary: "Update #{singular} fields",
        description: "Partial update; only the supplied fields change.",
        auth: :rw,
        params: [id_param],
        request_body: %{
          description: "Fields to change",
          schema: schema,
          example: Map.take(example, ["title", "description"])
        },
        responses:
          [ok(@json, "Updated #{singular}", schema)] ++ write_errors ++ [err(404, "Not found")]
      },
      %{
        id: "manage-#{plural}-delete",
        method: "DELETE",
        path: "#{base}/{#{singular}_id}",
        summary: "Delete #{singular}",
        description: "Removes the #{singular}.",
        auth: :rw,
        params: [id_param],
        request_body: nil,
        responses: [
          ok(@json, "Deleted", nil),
          err(401, "Missing or non-RW key"),
          err(404, "Not found")
        ]
      }
    ]
  end

  defp items_crud(item_example) do
    [list, show, create, update, patch, delete] =
      crud("items", "item", "Item", "ItemList", item_example, "dem_10m_clipped")

    list =
      list
      |> Map.put(:params, [limit_param(10, 100), offset_param()])
      |> Map.put(:description, "Paginated list of all items with self / next / prev links.")

    create =
      Map.put(
        create,
        :description,
        "Creates one STAC Item. geometry and collection are required; properties must carry either " <>
          "datetime or both start_datetime and end_datetime. Assets are normalised into their own table " <>
          "and the parent collection extent is updated."
      )

    import_ep = %{
      id: "manage-items-import",
      method: "POST",
      path: "/stac/manage/v1/items/import",
      summary: "Bulk import items",
      description:
        "Upserts many items in one request. Each feature is validated on its own; the response counts " <>
          "successes and failures instead of failing the whole batch.",
      auth: :rw,
      params: [],
      request_body: %{
        description: "FeatureCollection-like object",
        schema: "BulkImportBody",
        example: %{"features" => [item_example]}
      },
      responses: [
        ok(@json, "Import summary", "BulkImportResult"),
        err(400, "Missing or empty features array"),
        err(401, "Missing or non-RW key")
      ]
    }

    [list, show, create, import_ep, update, patch, delete]
  end

  # --- Web interface -------------------------------------------------------------

  defp web_endpoints do
    [
      %{
        id: "web-landing",
        method: "GET",
        path: "/stac/web/",
        summary: "Web landing page",
        description: "Overview page with links to the browser, search and API.",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [%{status: 200, media: @html, description: "HTML page", schema: nil}]
      },
      %{
        id: "web-browse",
        method: "GET",
        path: "/stac/web/browse",
        summary: "Data browser",
        description:
          "Browse catalogs, collections and items. Deeper paths follow " <>
            "/browse/catalog/{id}, /browse/collection/{id} and /browse/collection/{id}/item/{item_id}.",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [%{status: 200, media: @html, description: "HTML page", schema: nil}]
      },
      %{
        id: "web-search",
        method: "GET",
        path: "/stac/web/search",
        summary: "Search form",
        description: "Interactive item search with a map preview of each result.",
        auth: :public,
        params: [],
        request_body: nil,
        responses: [%{status: 200, media: @html, description: "HTML page", schema: nil}]
      },
      %{
        id: "web-search-api",
        method: "GET",
        path: "/stac/web/search/api",
        summary: "Search (session-authenticated JSON)",
        description:
          "Same filters and response as the STAC search, but private content is decided by the " <>
            "browser session instead of the X-API-Key header. Used by the search form's JSON button.",
        auth: :public,
        params: search_params(:get),
        request_body: nil,
        example_query: "collections=estonia-soil&limit=2",
        responses: [ok(@geojson, "Matching items", "ItemCollection")]
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Examples
  # ---------------------------------------------------------------------------

  @doc "Path with `{param}` placeholders replaced by their examples and the example query appended."
  def example_path(ep) do
    path =
      Enum.reduce(ep.params, ep.path, fn
        %{in: :path, name: name, example: ex}, acc when is_binary(ex) ->
          String.replace(acc, "{#{name}}", ex)

        _, acc ->
          acc
      end)

    case Map.get(ep, :example_query) do
      q when is_binary(q) and q != "" -> path <> "?" <> q
      _ -> path
    end
  end

  @doc """
  Relative URL to open a GET endpoint in the browser. Nil for other methods and
  for read-write endpoints, which a plain browser request cannot authenticate.
  """
  def try_href(%{method: "GET", auth: auth} = ep) when auth != :rw, do: example_path(ep)
  def try_href(_), do: nil

  @doc "A curl invocation for the endpoint."
  def curl_example(ep, base \\ base_url()) do
    url = base <> example_path(ep)

    parts =
      ["curl -s"] ++
        if(ep.method != "GET", do: ["-X #{ep.method}"], else: []) ++
        if(ep.auth == :rw, do: [~s(-H "X-API-Key: $STAC_API_KEY")], else: []) ++
        case ep.request_body do
          %{example: example} when is_map(example) ->
            [~s(-H "Content-Type: application/json"), ~s(-d '#{Jason.encode!(example)}')]

          _ ->
            []
        end ++
        [~s("#{url}")]

    Enum.join(parts, " \\\n  ")
  end

  # ---------------------------------------------------------------------------
  # OpenAPI 3.0
  # ---------------------------------------------------------------------------

  @doc """
  OpenAPI 3.0 document. Pass `include_management: true` to add the Management
  API paths and schemas; the default document only describes read access.
  """
  def openapi_spec(base \\ base_url(), opts \\ []) do
    include_management = Keyword.get(opts, :include_management, false)

    %{
      openapi: @openapi_version,
      info: %{
        title: @title,
        description: @description,
        version: app_version(),
        contact: %{
          name: "Landscape Geoinformatics Lab, University of Tartu",
          url: "https://landscape-geoinformatics.ut.ee"
        }
      },
      servers: [%{url: base, description: "This server"}],
      tags: Enum.map(groups(opts), &%{name: &1.tag, description: &1.description}),
      paths: openapi_paths(opts),
      components: %{
        securitySchemes: %{
          ApiKeyAuth: %{
            type: "apiKey",
            in: "header",
            name: "X-API-Key",
            description:
              if(include_management,
                do:
                  "Read-only keys unlock private catalogs on the STAC API; read-write keys additionally " <>
                    "allow the Management API.",
                else: "An API key unlocks private catalogs on the STAC API."
              )
          }
        },
        schemas: schemas(include_management)
      }
    }
  end

  defp openapi_paths(opts) do
    Enum.reduce(endpoints(opts), %{}, fn ep, acc ->
      Map.update(
        acc,
        ep.path,
        %{method_key(ep) => operation(ep)},
        &Map.put(&1, method_key(ep), operation(ep))
      )
    end)
  end

  defp method_key(ep), do: ep.method |> String.downcase() |> String.to_atom()

  defp operation(ep) do
    op = %{
      operationId: ep.id,
      tags: [ep.tag],
      summary: ep.summary,
      description: ep.description,
      parameters: Enum.map(ep.params, &parameter/1),
      responses: responses(ep.responses)
    }

    op =
      case ep.request_body do
        %{} = body ->
          Map.put(op, :requestBody, %{
            required: true,
            description: body.description,
            content: %{@json => %{schema: schema_ref(body.schema), example: body.example}}
          })

        _ ->
          op
      end

    case ep.auth do
      :rw -> Map.put(op, :security, [%{ApiKeyAuth: []}])
      :optional -> Map.put(op, :security, [%{}, %{ApiKeyAuth: []}])
      _ -> op
    end
  end

  defp parameter(p) do
    %{
      name: p.name,
      in: to_string(p.in),
      required: p.required,
      description: p.description,
      schema: %{type: p.type}
    }
    |> then(fn m -> if p.example, do: Map.put(m, :example, p.example), else: m end)
  end

  defp responses(list) do
    Map.new(list, fn r ->
      body =
        case r.schema do
          nil ->
            %{description: r.description}

          schema ->
            %{description: r.description, content: %{r.media => %{schema: schema_ref(schema)}}}
        end

      {Integer.to_string(r.status), body}
    end)
  end

  defp schema_ref(name), do: %{"$ref" => "#/components/schemas/#{name}"}

  @management_only_schemas [:CatalogList, :ItemList, :BulkImportBody, :BulkImportResult]

  defp schemas(include_management) do
    if include_management,
      do: all_schemas(),
      else: Map.drop(all_schemas(), @management_only_schemas)
  end

  defp all_schemas do
    link = %{
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

    links = %{type: "array", items: schema_ref("Link")}

    %{
      Link: link,
      Error: %{
        type: "object",
        properties: %{error: %{type: "string"}, message: %{type: "string"}}
      },
      Conformance: %{
        type: "object",
        required: ["conformsTo"],
        properties: %{conformsTo: %{type: "array", items: %{type: "string"}}}
      },
      Catalog: %{
        type: "object",
        required: ["stac_version", "id", "type", "links"],
        properties: %{
          stac_version: %{type: "string"},
          id: %{type: "string"},
          title: %{type: "string"},
          description: %{type: "string"},
          type: %{type: "string", enum: ["Catalog"]},
          private: %{type: "boolean"},
          parent_catalog_id: %{type: "string", nullable: true},
          conformsTo: %{type: "array", items: %{type: "string"}},
          links: links
        }
      },
      CatalogList: %{
        type: "object",
        properties: %{catalogs: %{type: "array", items: schema_ref("Catalog")}, links: links}
      },
      Collection: %{
        type: "object",
        required: ["stac_version", "id", "type", "links"],
        properties: %{
          stac_version: %{type: "string"},
          stac_extensions: %{type: "array", items: %{type: "string"}},
          id: %{type: "string"},
          title: %{type: "string"},
          description: %{type: "string"},
          type: %{type: "string", enum: ["Collection"]},
          license: %{type: "string"},
          keywords: %{type: "array", items: %{type: "string"}},
          providers: %{type: "array", items: %{type: "object"}},
          summaries: %{type: "object"},
          extent: %{
            type: "object",
            properties: %{
              spatial: %{
                type: "object",
                properties: %{
                  bbox: %{type: "array", items: %{type: "array", items: %{type: "number"}}}
                }
              },
              temporal: %{
                type: "object",
                properties: %{
                  interval: %{
                    type: "array",
                    items: %{type: "array", items: %{type: "string", nullable: true}}
                  }
                }
              }
            }
          },
          catalog_id: %{type: "string", nullable: true},
          links: links
        }
      },
      CollectionList: %{
        type: "object",
        properties: %{
          collections: %{type: "array", items: schema_ref("Collection")},
          links: links
        }
      },
      Item: %{
        type: "object",
        required: ["type", "id", "geometry", "properties"],
        properties: %{
          type: %{type: "string", enum: ["Feature"]},
          stac_version: %{type: "string"},
          stac_extensions: %{type: "array", items: %{type: "string"}},
          id: %{type: "string"},
          collection: %{type: "string"},
          geometry: %{type: "object", description: "GeoJSON geometry in WGS 84"},
          bbox: %{type: "array", items: %{type: "number"}},
          properties: %{
            type: "object",
            description:
              "STAC common metadata; datetime or start_datetime + end_datetime is required",
            properties: %{
              datetime: %{type: "string", nullable: true},
              start_datetime: %{type: "string"},
              end_datetime: %{type: "string"},
              created: %{type: "string"},
              updated: %{type: "string"}
            }
          },
          assets: %{type: "object", additionalProperties: schema_ref("Asset")},
          links: links
        }
      },
      Asset: %{
        type: "object",
        required: ["href"],
        properties: %{
          href: %{type: "string"},
          type: %{type: "string"},
          title: %{type: "string"},
          description: %{type: "string"},
          roles: %{type: "array", items: %{type: "string"}},
          "file:size": %{type: "integer"},
          "raster:bands": %{type: "array", items: %{type: "object"}},
          alternate: %{type: "object", description: "Alternate hrefs keyed by name, e.g. s3"}
        }
      },
      ItemCollection: %{
        type: "object",
        required: ["type", "features"],
        properties: %{
          type: %{type: "string", enum: ["FeatureCollection"]},
          features: %{type: "array", items: schema_ref("Item")},
          links: links,
          context: %{
            type: "object",
            properties: %{
              returned: %{type: "integer"},
              matched: %{type: "integer"},
              limit: %{type: "integer"}
            }
          }
        }
      },
      ItemList: %{
        type: "object",
        properties: %{items: %{type: "array", items: schema_ref("Item")}, links: links}
      },
      SearchBody: %{
        type: "object",
        properties: %{
          collections: %{type: "array", items: %{type: "string"}},
          ids: %{type: "array", items: %{type: "string"}},
          bbox: %{type: "array", items: %{type: "number"}, minItems: 4, maxItems: 6},
          datetime: %{
            type: "string",
            description: "RFC 3339 instant or start/end interval, '..' for open ends"
          },
          intersects: %{type: "object", description: "GeoJSON geometry"},
          limit: %{type: "integer", minimum: 1, maximum: 100, default: 10},
          offset: %{type: "integer", minimum: 0, default: 0}
        }
      },
      BulkImportBody: %{
        type: "object",
        required: ["features"],
        properties: %{features: %{type: "array", items: schema_ref("Item"), minItems: 1}}
      },
      BulkImportResult: %{
        type: "object",
        properties: %{
          success: %{type: "boolean"},
          message: %{type: "string"},
          imported: %{type: "integer"},
          failed: %{type: "integer"},
          total: %{type: "integer"}
        }
      }
    }
  end
end
