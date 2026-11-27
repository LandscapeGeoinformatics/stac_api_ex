defmodule StacApiWeb.CollectionsController do
  use StacApiWeb, :controller
  alias StacApi.Data.{Catalog, Collection, ItemFields, ItemListing, Search}
  alias StacApi.Repo
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  def index(conn, _params) do
    try do
      authenticated = conn.assigns[:authenticated] || false

      collections_query =
        if authenticated do
          from(c in Collection)
        else
          from(c in Collection,
            left_join: cat in Catalog,
            on: c.catalog_id == cat.id,
            where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
          )
        end

      collections = Repo.all(collections_query)

      # data sanitization and link resolution
      safe_collections =
        Enum.map(collections, fn collection ->
          sanitized = sanitize_collection(collection)
          custom_links = collection.links || []

          links =
            StacApiWeb.DynamicLinkGenerator.generate_collection_links(collection, custom_links)

          Map.put(sanitized, :links, links)
        end)

      json(conn, %{
        collections: safe_collections,
        links: [
          LinkResolver.create_link("root", "/stac/api/v1/"),
          LinkResolver.create_link("self", "/stac/api/v1/collections"),
          LinkResolver.create_link("search", "/stac/api/v1/search", type: "application/geo+json")
        ]
      })
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch collections: #{inspect(error)}"})
    end
  end

  def show(conn, %{"id" => id}) do
    try do
      authenticated = conn.assigns[:authenticated] || false

      case Repo.get(Collection, id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Collection not found"})

        collection ->
          # Check if collection is in a private catalog
          catalog_check =
            if collection.catalog_id do
              case Repo.get(Catalog, collection.catalog_id) do
                nil ->
                  :ok

                catalog ->
                  catalog_private = catalog.private == true

                  if catalog_private && !authenticated do
                    :private
                  else
                    :ok
                  end
              end
            else
              :ok
            end

          if catalog_check == :private do
            conn
            |> put_status(:not_found)
            |> json(%{error: "Collection not found"})
          else
            safe_collection = sanitize_collection(collection)
            custom_links = collection.links || []

            resolved_links =
              StacApiWeb.DynamicLinkGenerator.generate_collection_links(collection, custom_links)

            # Return as proper STAC Collection object
            stac_collection =
              Map.merge(safe_collection, %{
                type: "Collection",
                links: resolved_links
              })

            json(conn, stac_collection)
          end
      end
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch collection: #{inspect(error)}"})
    end
  end

  def items(conn, %{"id" => collection_id} = params) do
    try do
      authenticated = conn.assigns[:authenticated] || false

      with {:ok, filters} <- StacApi.Data.ItemFilters.parse(params),
           {:ok, fields} <- ItemFields.parse(params, :get),
           {:ok, listing} <- ItemListing.parse(params) do
        case Repo.get(Collection, collection_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Collection not found"})

          collection ->
            # Check if collection is in a private catalog
            catalog_check =
              if collection.catalog_id do
                case Repo.get(Catalog, collection.catalog_id) do
                  nil ->
                    :ok

                  catalog ->
                    catalog_private = catalog.private == true

                    if catalog_private && !authenticated do
                      :private
                    else
                      :ok
                    end
                end
              else
                :ok
              end

            if catalog_check == :private do
              conn
              |> put_status(:not_found)
              |> json(%{error: "Collection not found"})
            else
              base_query = from(i in StacApi.Data.Item, where: i.collection_id == ^collection_id)

              base_query = StacApi.Data.ItemFilters.apply(base_query, filters)
              total_count = Repo.aggregate(base_query, :count, :id)

              items = base_query |> ItemListing.apply(listing) |> Repo.all()
              %{limit: limit, offset: offset} = listing

              sanitized_items =
                Enum.map(items, fn item ->
                  item
                  |> Search.serialize_item_for_api()
                  |> ItemFields.project(fields)
                end)

              base_url = Application.get_env(:stac_api, :base_url, "")
              items_base = "#{base_url}/stac/api/v1/collections/#{collection_id}/items"

              pagination_params =
                params
                |> ItemFields.pagination_params(fields)
                |> ItemListing.pagination_params(listing)

              page_url = fn page_offset ->
                page_params = [{"limit", limit}, {"offset", page_offset}]

                page_params =
                  if pagination_params["datetime"],
                    do: page_params ++ [{"datetime", pagination_params["datetime"]}],
                    else: page_params

                page_params =
                  if pagination_params["bbox"],
                    do: page_params ++ [{"bbox", pagination_params["bbox"]}],
                    else: page_params

                page_params =
                  if Map.has_key?(pagination_params, "fields"),
                    do: page_params ++ [{"fields", pagination_params["fields"]}],
                    else: page_params

                page_params =
                  if pagination_params["sortby"],
                    do: page_params ++ [{"sortby", pagination_params["sortby"]}],
                    else: page_params

                "#{items_base}?#{URI.encode_query(page_params)}"
              end

              pagination_links =
                [
                  %{
                    "rel" => "self",
                    "href" => page_url.(offset),
                    "type" => "application/geo+json"
                  },
                  %{
                    "rel" => "root",
                    "href" => "#{base_url}/stac/api/v1/",
                    "type" => "application/json"
                  },
                  %{
                    "rel" => "collection",
                    "href" => "#{base_url}/stac/api/v1/collections/#{collection_id}",
                    "type" => "application/json"
                  }
                ] ++
                  if offset + limit < total_count do
                    [
                      %{
                        "rel" => "next",
                        "href" => page_url.(offset + limit),
                        "type" => "application/geo+json"
                      }
                    ]
                  else
                    []
                  end ++
                  if offset > 0 do
                    [
                      %{
                        "rel" => "prev",
                        "href" => page_url.(max(offset - limit, 0)),
                        "type" => "application/geo+json"
                      }
                    ]
                  else
                    []
                  end

              conn
              |> put_resp_content_type("application/geo+json")
              |> json(%{
                type: "FeatureCollection",
                features: sanitized_items,
                numberMatched: total_count,
                numberReturned: length(sanitized_items),
                links: pagination_links,
                context: %{
                  returned: length(sanitized_items),
                  matched: total_count,
                  limit: limit
                }
              })
            end
        end
      else
        {:error, parameter, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Invalid #{parameter} parameter: it #{reason}"})
      end
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch collection items: #{inspect(error)}"})
    end
  end

  def show_item(conn, %{"collection_id" => collection_id, "item_id" => item_id}) do
    try do
      authenticated = conn.assigns[:authenticated] || false

      # Check collection exists and its catalog is not private
      catalog_check =
        case Repo.get(Collection, collection_id) do
          nil ->
            :not_found

          collection ->
            if collection.catalog_id do
              case Repo.get(Catalog, collection.catalog_id) do
                nil ->
                  :ok

                catalog ->
                  if catalog.private == true && !authenticated, do: :private, else: :ok
              end
            else
              :ok
            end
        end

      case catalog_check do
        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Item not found"})

        :private ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Item not found"})

        :ok ->
          query =
            from(i in StacApi.Data.Item,
              where: i.collection_id == ^collection_id and i.id == ^item_id
            )

          case Repo.one(query) do
            nil ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Item not found"})

            item ->
              conn
              |> put_resp_content_type("application/geo+json")
              |> json(Search.serialize_item_for_api(item))
          end
      end
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch item: #{inspect(error)}"})
    end
  end

  # data sanitization
  defp sanitize_collection(collection) do
    %{
      type: "Collection",
      id: collection.id || "",
      title: collection.title || "",
      description: collection.description || "",
      license: collection.license || "",
      extent: collection.extent || %{},
      summaries: collection.summaries || %{},
      stac_version: collection.stac_version || "",
      stac_extensions: collection.stac_extensions || [],
      links: collection.links || []
    }
    |> maybe_put_collection_field(:keywords, Map.get(collection, :keywords))
    |> maybe_put_collection_field(:providers, Map.get(collection, :providers))
  end

  defp maybe_put_collection_field(map, _key, nil), do: map
  defp maybe_put_collection_field(map, _key, []), do: map
  defp maybe_put_collection_field(map, key, value), do: Map.put(map, key, value)
end
