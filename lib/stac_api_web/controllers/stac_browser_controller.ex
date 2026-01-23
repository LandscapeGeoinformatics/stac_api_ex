defmodule StacApiWeb.StacBrowserController do
  use StacApiWeb, :controller
  require Logger
  alias StacApi.Repo
  alias StacApi.Data.{Catalog, Collection, Item, Search}
  import Ecto.Query

  def landing(conn, _params) do
    render(conn, :landing)
  end

  def index(conn, _params) do
    catalogs = Repo.all(from c in Catalog, where: c.depth == 0, order_by: [asc: c.id])
    
    root_collections = Repo.all(
      from c in Collection,
      where: is_nil(c.catalog_id),
      order_by: [asc: c.id]
    )
    
    items = catalogs
    |> Enum.map(fn catalog ->
      %{
        id: catalog.id,
        title: catalog.title || catalog.id,
        description: catalog.description,
        type: "Catalog",
        path: "catalog/#{catalog.id}",
        is_directory: true
      }
    end)
    
    collection_items = root_collections
    |> Enum.map(fn collection ->
      item_count = Repo.aggregate(
        from(i in Item, where: i.collection_id == ^collection.id),
        :count,
        :id
      )
      
      %{
        id: collection.id,
        title: collection.title || collection.id,
        description: collection.description,
        type: "Collection",
        path: "collection/#{collection.id}",
        is_directory: true,
        item_count: item_count
      }
    end)
    
    all_items = items ++ collection_items
    
    conn
    |> assign(:items, all_items)
    |> assign(:current_path, "")
    |> assign(:breadcrumbs, [%{name: "Home", path: ""}])
    |> assign(:collection_path, nil)
    |> assign(:current_type, :root)
    |> assign(:current_entity, nil)
    |> render(:index)
  end

  def show(conn, %{"path" => path_segments}) when is_list(path_segments) do
    path = Enum.join(path_segments, "/")
    browse_path(conn, path)
  end

  def show(conn, %{"path" => path}) when is_binary(path) do
    browse_path(conn, path)
  end

  def show(conn, _params) do
    redirect(conn, to: ~p"/stac/web/browse")
  end

  def search(conn, params) do
    search_params = normalize_search_params(params)

    case search_params do
      %{} when map_size(search_params) == 0 ->
        conn
        |> assign(:search_results, [])
        |> assign(:search_params, %{})
        |> assign(:total_count, 0)
        |> render(:search)

      _ ->
        items = Search.search(search_params)
        total_count = Search.count_search_results(search_params)

        conn
        |> assign(:search_results, items)
        |> assign(:search_params, search_params)
        |> assign(:total_count, total_count)
        |> render(:search)
    end
  end

  def search_api(conn, params) do
    search_params = normalize_search_params(params)

    items = Search.search(search_params)
    total_count = Search.count_search_results(search_params)

    features = Enum.map(items, &Search.serialize_item_for_api/1)

    response = %{
      "type" => "FeatureCollection",
      "features" => features,
      "context" => %{
        "returned" => length(features),
        "matched" => total_count,
        "limit" => parse_int(search_params["limit"] || "10")
      }
    }

    conn
    |> put_resp_content_type("application/geo+json")
    |> json(response)
  end

  defp browse_path(conn, path) do
    case parse_path(path) do
      {:catalog, catalog_id} ->
        show_catalog(conn, catalog_id, path)
      
      {:collection, collection_id} ->
        show_collection(conn, collection_id, path)
      
      {:item, collection_id, item_id} ->
        show_item(conn, collection_id, item_id, path)
      
      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid path")
        |> redirect(to: ~p"/stac/web/browse")
    end
  end

  defp parse_path(path) do
    case String.split(path, "/", trim: true) do
      ["catalog", catalog_id] ->
        {:catalog, catalog_id}
      
      ["catalog", catalog_id, "collection", collection_id] ->
        {:collection, collection_id}
      
      ["collection", collection_id] ->
        {:collection, collection_id}
      
      ["catalog", _catalog_id, "collection", collection_id, "item", item_id] ->
        {:item, collection_id, item_id}
      
      ["collection", collection_id, "item", item_id] ->
        {:item, collection_id, item_id}
      
      _ ->
        {:error, :invalid_path}
    end
  end

  defp show_catalog(conn, catalog_id, path) do
    case Repo.get(Catalog, catalog_id) do
      nil ->
        conn
        |> put_flash(:error, "Catalog not found")
        |> redirect(to: ~p"/stac/web/browse")
      
      catalog ->
        child_catalogs = Repo.all(
          from c in Catalog,
          where: c.parent_catalog_id == ^catalog_id,
          order_by: [asc: c.id]
        )
        
        collections = Repo.all(
          from c in Collection,
          where: c.catalog_id == ^catalog_id,
          order_by: [asc: c.id]
        )
        
        catalog_items = child_catalogs
        |> Enum.map(fn child_catalog ->
          %{
            id: child_catalog.id,
            title: child_catalog.title || child_catalog.id,
            description: child_catalog.description,
            type: "Catalog",
            path: "#{path}/catalog/#{child_catalog.id}",
            is_directory: true
          }
        end)
        
        collection_items = collections
        |> Enum.map(fn collection ->
          item_count = Repo.aggregate(
            from(i in Item, where: i.collection_id == ^collection.id),
            :count,
            :id
          )
          
          %{
            id: collection.id,
            title: collection.title || collection.id,
            description: collection.description,
            type: "Collection",
            path: "#{path}/collection/#{collection.id}",
            is_directory: true,
            item_count: item_count
          }
        end)
        
        all_items = catalog_items ++ collection_items
        breadcrumbs = build_breadcrumbs_from_catalog(catalog)
        
        conn
        |> assign(:items, all_items)
        |> assign(:current_path, path)
        |> assign(:breadcrumbs, breadcrumbs)
        |> assign(:collection_path, nil)
        |> assign(:current_type, :catalog)
        |> assign(:current_entity, catalog)
        |> render(:index)
    end
  end

  defp show_collection(conn, collection_id, path) do
    case Repo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_flash(:error, "Collection not found")
        |> redirect(to: ~p"/stac/web/browse")
      
      collection ->
        items_query = from i in Item,
          where: i.collection_id == ^collection_id,
          order_by: [desc: i.datetime],
          limit: 100
        
        items = Repo.all(items_query)
        
        item_entries = items
        |> Enum.map(fn item ->
          %{
            id: item.id,
            title: get_in(item.properties, ["title"]) || item.id,
            description: get_in(item.properties, ["description"]),
            type: "Item",
            path: "#{path}/item/#{item.id}",
            is_directory: false,
            datetime: item.datetime,
            properties: item.properties
          }
        end)
        
        breadcrumbs = build_breadcrumbs_from_collection(collection)
        
        conn
        |> assign(:items, item_entries)
        |> assign(:current_path, path)
        |> assign(:breadcrumbs, breadcrumbs)
        |> assign(:collection_path, collection_id)
        |> assign(:current_type, :collection)
        |> assign(:current_entity, collection)
        |> render(:index)
    end
  end

  defp show_item(conn, collection_id, item_id, path) do
    case Repo.get(Item, item_id) do
      nil ->
        conn
        |> put_flash(:error, "Item not found")
        |> redirect(to: ~p"/stac/web/browse")
      
      item ->
        if item.collection_id != collection_id do
          conn
          |> put_flash(:error, "Item not found in this collection")
          |> redirect(to: ~p"/stac/web/browse")
        else
          collection = Repo.get(Collection, collection_id)
          
          assets = reconstruct_item_assets(item.id, item.stac_extensions || [])
          
          item_data = %{
            type: "Feature",
            stac_version: item.stac_version || "1.0.0",
            stac_extensions: item.stac_extensions || [],
            id: item.id,
            geometry: item.geometry,
            bbox: item.bbox,
            properties: item.properties || %{},
            assets: assets,
            collection: item.collection_id
          }
          
          breadcrumbs = build_breadcrumbs_from_item(item, collection)
          
          conn
          |> assign(:item, item_data)
          |> assign(:current_path, path)
          |> assign(:breadcrumbs, breadcrumbs)
          |> assign(:collection_path, collection_id)
          |> assign(:current_type, :item)
          |> assign(:current_entity, item)
          |> render(:item)
        end
    end
  end

  defp build_breadcrumbs_from_catalog(catalog) do
    breadcrumbs = [%{name: "Home", path: ""}]
    
    if catalog.parent_catalog_id do
      case Repo.get(Catalog, catalog.parent_catalog_id) do
        nil -> breadcrumbs
        parent ->
          breadcrumbs ++ [
            %{name: parent.title || parent.id, path: "catalog/#{parent.id}"},
            %{name: catalog.title || catalog.id, path: "catalog/#{catalog.id}"}
          ]
      end
    else
      breadcrumbs ++ [%{name: catalog.title || catalog.id, path: "catalog/#{catalog.id}"}]
    end
  end

  defp build_breadcrumbs_from_collection(collection) do
    breadcrumbs = [%{name: "Home", path: ""}]
    
    if collection.catalog_id do
      case Repo.get(Catalog, collection.catalog_id) do
        nil -> 
          breadcrumbs ++ [%{name: collection.title || collection.id, path: "collection/#{collection.id}"}]
        
        catalog ->
          catalog_breadcrumbs = if catalog.parent_catalog_id do
            case Repo.get(Catalog, catalog.parent_catalog_id) do
              nil -> []
              parent -> [%{name: parent.title || parent.id, path: "catalog/#{parent.id}"}]
            end
          else
            []
          end
          
          breadcrumbs ++ 
          catalog_breadcrumbs ++ 
          [
            %{name: catalog.title || catalog.id, path: "catalog/#{catalog.id}"},
            %{name: collection.title || collection.id, path: "catalog/#{catalog.id}/collection/#{collection.id}"}
          ]
      end
    else
      breadcrumbs ++ [%{name: collection.title || collection.id, path: "collection/#{collection.id}"}]
    end
  end

  defp build_breadcrumbs_from_item(item, collection) do
    collection_breadcrumbs = build_breadcrumbs_from_collection(collection)
    item_title = get_in(item.properties, ["title"]) || item.id
    
    if collection.catalog_id do
      collection_path = "catalog/#{collection.catalog_id}/collection/#{collection.id}"
      collection_breadcrumbs ++ [%{name: item_title, path: "#{collection_path}/item/#{item.id}"}]
    else
      collection_path = "collection/#{collection.id}"
      collection_breadcrumbs ++ [%{name: item_title, path: "#{collection_path}/item/#{item.id}"}]
    end
  end

  defp reconstruct_item_assets(item_id, stac_extensions) do
    assets = Repo.all(from a in StacApi.Data.ItemAsset, where: a.item_id == ^item_id)
    
    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = StacApi.Data.ItemAsset.to_stac_asset(asset, stac_extensions)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end

  defp normalize_search_params(params) do
    params
    |> Enum.into(%{}, fn
      {key, value} when is_atom(key) -> {to_string(key), value}
      {key, value} -> {key, value}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0
end
