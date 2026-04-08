defmodule StacApiWeb.CollectionsController do
  use StacApiWeb, :controller
  alias StacApi.Data.{Collection, ItemAsset, Catalog}
  alias StacApi.Repo
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  def index(conn, _params) do
    try do
      authenticated = conn.assigns[:authenticated] || false
      
      collections_query = if authenticated do
        from c in Collection
      else
        from c in Collection,
          left_join: cat in Catalog, on: c.catalog_id == cat.id,
          where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
      end
      
      collections = Repo.all(collections_query)

     # data sanitization and link resolution
      safe_collections = Enum.map(collections, fn collection ->
        sanitized = sanitize_collection(collection)
        custom_links = collection.links || []
        links = StacApiWeb.DynamicLinkGenerator.generate_collection_links(collection, custom_links)
        Map.put(sanitized, :links, links)
      end)

      json(conn, %{
        collections: safe_collections,
        links: [
          LinkResolver.create_link("root", "/stac/api/v1/"),
          LinkResolver.create_link("self", "/stac/api/v1/collections"),
          LinkResolver.create_link("search", "/stac/api/v1/search",
            type: "application/geo+json"
          )
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
          catalog_check = if collection.catalog_id do
            case Repo.get(Catalog, collection.catalog_id) do
              nil -> :ok
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
            resolved_links = StacApiWeb.DynamicLinkGenerator.generate_collection_links(collection, custom_links)
            
            # Return as proper STAC Collection object
            stac_collection = Map.merge(safe_collection, %{
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

      limit = parse_int(params["limit"] || "10") |> max(1) |> min(10_000)
      offset = parse_int(params["offset"] || "0") |> max(0)

      case Repo.get(Collection, collection_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Collection not found"})

        collection ->
          # Check if collection is in a private catalog
          catalog_check = if collection.catalog_id do
            case Repo.get(Catalog, collection.catalog_id) do
              nil -> :ok
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
            base_query = from i in StacApi.Data.Item,
              where: i.collection_id == ^collection_id,
              order_by: [desc: i.datetime]

            total_count = Repo.aggregate(base_query, :count, :id)

            items = Repo.all(from i in base_query, limit: ^limit, offset: ^offset)

            sanitized_items = Enum.map(items, fn item ->
              sanitized = sanitize_item(item)
              assets = reconstruct_item_assets(item.id, item.stac_extensions || [])
              sanitized = Map.put(sanitized, :assets, assets)

              custom_links = item.links || []
              links = StacApiWeb.DynamicLinkGenerator.generate_item_links(item, custom_links)
              Map.put(sanitized, :links, links)
            end)

            base_url = Application.get_env(:stac_api, :base_url, "")
            items_base = "#{base_url}/stac/api/v1/collections/#{collection_id}/items"

            pagination_links =
              [
                %{"rel" => "self", "href" => "#{items_base}?limit=#{limit}&offset=#{offset}", "type" => "application/geo+json"},
                %{"rel" => "root", "href" => "#{base_url}/stac/api/v1/", "type" => "application/json"},
                %{"rel" => "collection", "href" => "#{base_url}/stac/api/v1/collections/#{collection_id}", "type" => "application/json"}
              ] ++
              (if offset + limit < total_count do
                [%{"rel" => "next", "href" => "#{items_base}?limit=#{limit}&offset=#{offset + limit}", "type" => "application/geo+json"}]
              else [] end) ++
              (if offset > 0 do
                prev_offset = max(offset - limit, 0)
                [%{"rel" => "prev", "href" => "#{items_base}?limit=#{limit}&offset=#{prev_offset}", "type" => "application/geo+json"}]
              else [] end)

            conn
            |> put_resp_content_type("application/geo+json")
            |> json(%{
              type: "FeatureCollection",
              features: sanitized_items,
              links: pagination_links,
              context: %{
                returned: length(sanitized_items),
                matched: total_count,
                limit: limit
              }
            })
          end
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
      catalog_check = case Repo.get(Collection, collection_id) do
        nil -> :not_found
        collection ->
          if collection.catalog_id do
            case Repo.get(Catalog, collection.catalog_id) do
              nil -> :ok
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
          query = from i in StacApi.Data.Item,
            where: i.collection_id == ^collection_id and i.id == ^item_id

          case Repo.one(query) do
            nil ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Item not found"})

            item ->
              sanitized_item = sanitize_item(item)
              assets = reconstruct_item_assets(item.id, item.stac_extensions || [])
              sanitized_item = Map.put(sanitized_item, :assets, assets)

              custom_links = item.links || []
              resolved_links = StacApiWeb.DynamicLinkGenerator.generate_item_links(item, custom_links)

              conn
              |> put_resp_content_type("application/geo+json")
              |> json(Map.put(sanitized_item, :links, resolved_links))
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

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0

  defp maybe_put_collection_field(map, _key, nil), do: map
  defp maybe_put_collection_field(map, _key, []), do: map
  defp maybe_put_collection_field(map, key, value), do: Map.put(map, key, value)

  defp sanitize_item(item) do
    %{
      type: "Feature",
      stac_version: item.stac_version || "",
      stac_extensions: item.stac_extensions || [],
      id: item.id || "",
      geometry: item.geometry,
      bbox: item.bbox || [],
      datetime: item.datetime,
      properties: item.properties || %{},
      links: item.links || [],
      collection: item.collection_id
    }
  end

  @doc """
  Reconstruct assets from normalized table back to STAC format
  """
  defp reconstruct_item_assets(item_id, stac_extensions \\ []) do
    assets = Repo.all(from a in ItemAsset, where: a.item_id == ^item_id)
    
    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = ItemAsset.to_stac_asset(asset, stac_extensions)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end
end
