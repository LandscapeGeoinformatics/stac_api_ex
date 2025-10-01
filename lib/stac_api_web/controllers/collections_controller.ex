defmodule StacApiWeb.CollectionsController do
  use StacApiWeb, :controller
  alias StacApi.Data.Collection
  alias StacApi.Repo
  alias StacApiWeb.LinkResolver
  import Ecto.Query

  def index(conn, _params) do
    try do
      collections = Repo.all(Collection)

     # data sanitization and link resolution
      safe_collections = Enum.map(collections, fn collection ->
        sanitized = sanitize_collection(collection)
        Map.put(sanitized, :links, LinkResolver.resolve_links(sanitized.links))
      end)

      json(conn, %{
        collections: safe_collections,
        links: [
          LinkResolver.create_link("root", "/api/stac/v1/"),
          LinkResolver.create_link("self", "/api/stac/v1/collections"),
          LinkResolver.create_link("search", "/api/stac/v1/search",
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
      case Repo.get(Collection, id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Collection not found"})

        collection ->
          safe_collection = sanitize_collection(collection)
          # Resolve links from database
          resolved_links = LinkResolver.resolve_links(safe_collection.links)
          
          # Return as proper STAC Collection object
          stac_collection = Map.merge(safe_collection, %{
            type: "Collection",
            links: resolved_links
          })
          
          json(conn, stac_collection)
      end
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch collection: #{inspect(error)}"})
    end
  end

  def items(conn, %{"id" => collection_id}) do
    try do
      query = from i in StacApi.Data.Item,
        where: i.collection_id == ^collection_id

      items = Repo.all(query)
      sanitized_items = Enum.map(items, fn item ->
        sanitized = sanitize_item(item)
        Map.put(sanitized, :links, LinkResolver.resolve_links(sanitized.links))
      end)

      json(conn, %{
        type: "FeatureCollection",
        features: sanitized_items,
        links: LinkResolver.create_item_links(collection_id)
      })
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch collection items: #{inspect(error)}"})
    end
  end

  def show_item(conn, %{"collection_id" => collection_id, "item_id" => item_id}) do
    try do
      query = from i in StacApi.Data.Item,
        where: i.collection_id == ^collection_id and i.id == ^item_id

      case Repo.one(query) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Item not found"})

        item ->
          sanitized_item = sanitize_item(item)
          resolved_links = LinkResolver.resolve_links(sanitized_item.links)
          
          json(conn, Map.put(sanitized_item, :links, resolved_links))
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
      id: collection.id || "",
      title: collection.title || "",
      description: collection.description || "",
      license: collection.license || "",
      extent: collection.extent || %{},
      summaries: collection.summaries || %{},
      properties: collection.properties || %{},
      stac_version: collection.stac_version || "",
      stac_extensions: collection.stac_extensions || [],
      links: collection.links || [],
      inserted_at: collection.inserted_at,
      updated_at: collection.updated_at
    }
  end

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
      assets: item.assets || %{},
      links: item.links || [],
      collection: item.collection_id
    }
  end
end
