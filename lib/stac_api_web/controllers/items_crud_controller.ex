defmodule StacApiWeb.ItemsCrudController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.{Item, Collection, ItemAsset}
  alias StacApiWeb.DynamicLinkGenerator
  import Ecto.Query

  @doc """
  POST /api/stac/v1/items
  Create or update an item (upsert based on ID)
  """
  def create(conn, params) do
    case validate_item_params(params) do
      {:ok, item_attrs} ->
        case upsert_item(item_attrs) do
          {:ok, item} ->
            # Normalize assets into separate table
            normalize_item_assets(item.id, item_attrs["assets"] || %{})
            
            # Generate links dynamically
            custom_links = Map.get(item_attrs, "links", [])
            links = DynamicLinkGenerator.generate_item_links(item, custom_links)
            
            # Reconstruct assets from normalized data
            assets = reconstruct_item_assets(item.id)
            
            item_response = %{
              type: "Feature",
              stac_version: item.stac_version || "1.0.0",
              stac_extensions: item.stac_extensions || [],
              id: item.id,
              geometry: item.geometry,
              bbox: item.bbox,
              properties: item.properties || %{},
              assets: assets,
              collection: item.collection_id,
              links: links
            }

            success_response = %{
              success: true,
              message: "Item created successfully",
              data: item_response
            }

            conn
            |> put_status(:created)
            |> json(success_response)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/stac/v1/items/:id
  Get a specific item
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        # Generate links dynamically
        custom_links = item.links || []
        links = DynamicLinkGenerator.generate_item_links(item, custom_links)
        
        # Reconstruct assets from normalized data
        assets = reconstruct_item_assets(item.id)
        
        item_response = %{
          type: "Feature",
          stac_version: item.stac_version || "1.0.0",
          stac_extensions: item.stac_extensions || [],
          id: item.id,
          geometry: item.geometry,
          bbox: item.bbox,
          properties: item.properties || %{},
          assets: assets,
          collection: item.collection_id,
          links: links
        }

        json(conn, item_response)
    end
  end

  @doc """
  PUT /api/stac/v1/items/:id
  Update a specific item
  """
  def update(conn, %{"id" => id} = params) do
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        case validate_item_params(params) do
          {:ok, item_attrs} ->
            case update_item(item, item_attrs) do
              {:ok, updated_item} ->
                # Normalize assets into separate table
                normalize_item_assets(updated_item.id, item_attrs["assets"] || %{})
                
                # Generate links dynamically
                custom_links = Map.get(item_attrs, "links", [])
                links = DynamicLinkGenerator.generate_item_links(updated_item, custom_links)
                
                # Reconstruct assets from normalized data
                assets = reconstruct_item_assets(updated_item.id)
                
                item_response = %{
                  type: "Feature",
                  stac_version: updated_item.stac_version || "1.0.0",
                  stac_extensions: updated_item.stac_extensions || [],
                  id: updated_item.id,
                  geometry: updated_item.geometry,
                  bbox: updated_item.bbox,
                  properties: updated_item.properties || %{},
                  assets: assets,
                  collection: updated_item.collection_id,
                  links: links
                }

                success_response = %{
                  success: true,
                  message: "Item updated successfully",
                  data: item_response
                }

                json(conn, success_response)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
            end

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: reason})
        end
    end
  end

  @doc """
  DELETE /api/stac/v1/items/:id
  Delete a specific item
  """
  def delete(conn, %{"id" => id}) do
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        case Repo.delete(item) do
            {:ok, _} ->
              conn
              |> put_status(:ok)
              |> json(%{
                success: true,
                message: "Item deleted successfully"
              })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete item", details: format_changeset_errors(changeset)})
        end
    end
  end

  @doc """
  GET /api/stac/v1/items
  List all items (with pagination)
  """
  def index(conn, params) do
    limit = min(parse_int(params["limit"] || "10"), 100)
    offset = parse_int(params["offset"] || "0")

    query = from(i in Item, limit: ^limit, offset: ^offset, order_by: [desc: i.datetime])
    items = Repo.all(query)
    total_count = Repo.aggregate(Item, :count, :id)
    
    items_with_links = Enum.map(items, fn item ->
      custom_links = item.links || []
      links = DynamicLinkGenerator.generate_item_links(item, custom_links)
      
      # Reconstruct assets from normalized data
      assets = reconstruct_item_assets(item.id)
      
      %{
        type: "Feature",
        stac_version: item.stac_version || "1.0.0",
        stac_extensions: item.stac_extensions || [],
        id: item.id,
        geometry: item.geometry,
        bbox: item.bbox,
        properties: item.properties || %{},
        assets: assets,
        collection: item.collection_id,
        links: links
      }
    end)

    json(conn, %{
      type: "FeatureCollection",
      features: items_with_links,
      links: [
        %{"rel" => "self", "href" => "/api/stac/v1/items", "type" => "application/geo+json"},
        %{"rel" => "root", "href" => "/api/stac/v1/", "type" => "application/json"}
      ],
      context: %{
        returned: length(items_with_links),
        matched: total_count,
        limit: limit
      }
    })
  end

  # Private helper functions

  defp validate_item_params(params) do
    required_fields = ["id", "collection_id", "geometry"]
    missing_fields = Enum.filter(required_fields, &is_nil(params[&1]))

    if length(missing_fields) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      # Validate collection_id exists
      collection_id = params["collection_id"]
      if !Repo.get(Collection, collection_id) do
        {:error, "Referenced collection does not exist"}
      else
        # Parse geometry if provided as GeoJSON string
        geometry = parse_geometry(params["geometry"])
        
        item_attrs = %{
          "id" => params["id"],
          "collection_id" => collection_id,
          "stac_version" => params["stac_version"] || "1.0.0",
          "stac_extensions" => params["stac_extensions"] || [],
          "geometry" => geometry,
          "bbox" => params["bbox"],
          "datetime" => parse_datetime(params["datetime"]),
          "properties" => params["properties"] || %{},
          "assets" => params["assets"] || %{},
          "links" => params["links"] || []
        }
        {:ok, item_attrs}
      end
    end
  end

  defp parse_geometry(nil), do: nil
  defp parse_geometry(geometry) when is_map(geometry) do
    case Geo.JSON.decode(geometry) do
      {:ok, geo_struct} -> geo_struct
      _ -> geometry
    end
  end
  defp parse_geometry(geometry_string) when is_binary(geometry_string) do
    case Jason.decode(geometry_string) do
      {:ok, geometry_map} -> parse_geometry(geometry_map)
      _ -> nil
    end
  end
  defp parse_geometry(geometry), do: geometry

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_datetime(datetime), do: datetime

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0

  defp upsert_item(attrs) do
    case Repo.get(Item, attrs["id"]) do
      nil ->
        %Item{}
        |> Item.changeset(attrs)
        |> Repo.insert()

      existing_item ->
        existing_item
        |> Item.changeset(attrs)
        |> Repo.update()
    end
  end

  defp update_item(item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Normalize assets from STAC format into separate table
  """
  defp normalize_item_assets(item_id, assets) when is_map(assets) do
    # First, delete existing assets for this item
    Repo.delete_all(from a in ItemAsset, where: a.item_id == ^item_id)
    
    # Insert new assets
    Enum.each(assets, fn {asset_key, asset_data} ->
      changeset = ItemAsset.from_stac_asset(item_id, asset_key, asset_data)
      case Repo.insert(changeset) do
        {:ok, _} -> :ok
        {:error, changeset} -> 
          IO.puts("Failed to insert asset #{asset_key}: #{inspect(changeset.errors)}")
      end
    end)
  end

  @doc """
  Reconstruct assets from normalized table back to STAC format
  """
  defp reconstruct_item_assets(item_id) do
    assets = Repo.all(from a in ItemAsset, where: a.item_id == ^item_id)
    
    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = ItemAsset.to_stac_asset(asset)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end
end
