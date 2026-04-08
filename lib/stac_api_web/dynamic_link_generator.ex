defmodule StacApiWeb.DynamicLinkGenerator do
  @moduledoc """
  Generates STAC links dynamically based on database relationships and context.
  
  This module replaces the static link storage approach with runtime link generation,
  making the API more flexible and maintainable.
  """

  alias StacApi.Repo
  alias StacApi.Data.{Catalog, Collection}
  import Ecto.Query

  @doc """
  Generates all links for a catalog based on its relationships and stored custom links.
  """
  def generate_catalog_links(catalog, custom_links \\ []) do
    runtime_links = generate_catalog_runtime_links(catalog)
    all_links = runtime_links ++ custom_links
    Enum.uniq_by(all_links, & &1["rel"])
  end

  @doc """
  Generates all links for a collection based on its relationships and stored custom links.
  """
  def generate_collection_links(collection, custom_links \\ []) do
    runtime_links = generate_collection_runtime_links(collection)
    all_links = runtime_links ++ custom_links
    Enum.uniq_by(all_links, & &1["rel"])
  end

  @doc """
  Generates all links for an item based on its relationships and stored custom links.
  """
  def generate_item_links(item, custom_links \\ []) do
    runtime_links = generate_item_runtime_links(item)
    all_links = runtime_links ++ custom_links
    Enum.uniq_by(all_links, & &1["rel"])
  end

  # Private functions for runtime link generation

  defp generate_catalog_runtime_links(catalog) do
    links = [
      # Self link
      create_link("self", "/stac/api/v1/catalog/#{catalog.id}"),
      # Root link
      create_link("root", "/stac/api/v1/")
    ]

    # Parent link (if not root catalog)
    parent_links = case catalog.parent_catalog_id do
      nil when catalog.id != "pygeoapi-stac" ->
        [create_link("parent", "/stac/api/v1/")]
      parent_id when is_binary(parent_id) ->
        [create_link("parent", "/stac/api/v1/catalog/#{parent_id}")]
      _ ->
        []
    end

    # Child catalogs
    child_catalogs = get_child_catalogs(catalog.id)
    catalog_child_links = Enum.map(child_catalogs, fn child ->
      create_link("child", "/stac/api/v1/catalog/#{child.id}", 
                  title: child.title || child.id)
    end)

    # Child collections
    child_collections = get_collections_in_catalog(catalog.id)
    collection_child_links = Enum.map(child_collections, fn collection ->
      create_link("child", "/stac/api/v1/collections/#{collection.id}",
                  title: collection.title || collection.id)
    end)

    links ++ parent_links ++ catalog_child_links ++ collection_child_links
  end

  defp generate_collection_runtime_links(collection) do
    links = [
      # Self link
      create_link("self", "/stac/api/v1/collections/#{collection.id}"),
      # Root link
      create_link("root", "/stac/api/v1/"),
      # Items link
      create_link("items", "/stac/api/v1/collections/#{collection.id}/items",
                  type: "application/geo+json")
    ]

    # Parent link — always point to the STAC root catalog.
    # Custom /catalog/ paths are not STAC-API conformant; catalogs are internal
    # grouping only and the spec has no /catalog/ route.
    parent_links = [create_link("parent", "/stac/api/v1/")]

    links ++ parent_links
  end

  defp generate_item_runtime_links(item) do
    # parent = the collection (STAC spec: parent is the direct container of the item)
    # Do NOT use /catalog/:id — that is a non-standard route and breaks conforming clients.
    [
      create_link("self", "/stac/api/v1/collections/#{item.collection_id}/items/#{item.id}"),
      create_link("root", "/stac/api/v1/"),
      create_link("parent", "/stac/api/v1/collections/#{item.collection_id}"),
      create_link("collection", "/stac/api/v1/collections/#{item.collection_id}")
    ]
  end

  # Helper functions for database queries

  defp get_child_catalogs(catalog_id) do
    from(c in Catalog, where: c.parent_catalog_id == ^catalog_id, order_by: c.id)
    |> Repo.all()
  end

  defp get_collections_in_catalog(catalog_id) do
    from(c in Collection, where: c.catalog_id == ^catalog_id, order_by: c.id)
    |> Repo.all()
  end

  # Helper function to create standardized links with absolute URLs
  defp create_link(rel, path, opts \\ []) do
    %{
      "rel" => rel,
      "href" => base_url() <> path,
      "type" => Keyword.get(opts, :type, "application/json"),
      "title" => Keyword.get(opts, :title),
      "method" => Keyword.get(opts, :method)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp base_url do
    Application.get_env(:stac_api, :base_url, "")
  end
end
