defmodule StacApiWeb.ItemsCrudController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.{Item, Collection, ItemAsset, Catalog}
  alias StacApiWeb.DynamicLinkGenerator
  import Ecto.Query

  @doc """
  POST /api/stac/v1/items/import
  """
  def bulk_import(conn, params) do
    features = Map.get(params, "features", [])

    if is_list(features) and length(features) > 0 do
      results = Enum.map(features, fn feature ->
        case validate_item_params(feature) do
          {:ok, item_attrs} ->
            case upsert_item(item_attrs) do
              {:ok, item} ->
                # Normalize assets into separate table
                normalize_item_assets(item.id, item_attrs["assets"] || %{})
                {:ok, item}
              {:error, changeset} ->
                {:error, item_attrs["id"], format_changeset_errors(changeset)}
            end
          {:error, reason} ->
            {:error, Map.get(feature, "id", "unknown"), reason}
        end
      end)

      # Update collection extents for all affected collections
      updated_collections = results
        |> Enum.filter(fn r -> match?({:ok, %Item{}}, r) end)
        |> Enum.map(fn {:ok, item} -> item.collection_id end)
        |> Enum.filter(& &1)
        |> Enum.uniq()

      Enum.each(updated_collections, &update_collection_extent/1)

      success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      error_count = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

      json(conn, %{
        success: true,
        message: "Bulk import completed",
        imported: success_count,
        failed: error_count,
        total: length(features)
      })
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Must provide 'features' array with at least one item"})
    end
  end

  @doc """
  POST /api/stac/v1/items
  Create a new item (returns 409 Conflict if ID already exists)
  """
  def create(conn, params) do
    case validate_item_params(params) do
      {:ok, item_attrs} ->
        item_id = item_attrs["id"]
        
        if Repo.get(Item, item_id) do
          conn
          |> put_status(:conflict)
          |> json(%{error: "Item with ID '#{item_id}' already exists"})
        else
          case create_item(item_attrs) do
            {:ok, item} ->
            normalize_item_assets(item.id, item_attrs["assets"] || %{})
            
            # Update collection extent after item creation
            if item.collection_id do
              update_collection_extent(item.collection_id)
            end

            custom_links = Map.get(item_attrs, "links", [])
            links = DynamicLinkGenerator.generate_item_links(item, custom_links)

            # Reconstruct assets from normalized data
            assets = reconstruct_item_assets(item.id, item.stac_extensions || [])

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
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/stac/v1/items/:id
  Get a specific item (returns 404 if in private catalog and not authenticated)
  """
  def show(conn, %{"id" => id}) do
    authenticated = conn.assigns[:authenticated] || false
    
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        catalog_check = if item.collection_id do
          collection = Repo.get(Collection, item.collection_id)
          if collection && collection.catalog_id do
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
        else
          :ok
        end
        
        if catalog_check == :private do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Item not found"})
        else
        custom_links = item.links || []
        links = DynamicLinkGenerator.generate_item_links(item, custom_links)
        assets = reconstruct_item_assets(item.id, item.stac_extensions || [])

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
  end

  @doc """
  PUT /api/stac/v1/items/:id
  Replace the entire item (full replacement - all fields required)
  """
  def update(conn, %{"id" => id} = params) do
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        case validate_item_params_full(params, id) do
          {:ok, item_attrs} ->
            case replace_item(item, item_attrs) do
              {:ok, updated_item} ->
            Repo.delete_all(from a in ItemAsset, where: a.item_id == ^id)
            normalize_item_assets(updated_item.id, item_attrs["assets"] || %{})
            
            # Update collection extent after item update
            if updated_item.collection_id do
              update_collection_extent(updated_item.collection_id)
            end

            custom_links = Map.get(item_attrs, "links", [])
            links = DynamicLinkGenerator.generate_item_links(updated_item, custom_links)
            assets = reconstruct_item_assets(updated_item.id, updated_item.stac_extensions || [])

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
                  message: "Item replaced successfully",
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
  PATCH /api/stac/v1/items/:id
  Partially update an item (only provided fields are updated)
  """
  def patch(conn, %{"id" => id} = params) do
    case Repo.get(Item, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      item ->
        case validate_item_params_partial(params) do
          {:ok, item_attrs} ->
            case update_item_partial(item, item_attrs) do
              {:ok, updated_item} ->
                reloaded_item = Repo.get(Item, id)
                
                if Map.has_key?(params, "assets") do
                  Repo.delete_all(from a in ItemAsset, where: a.item_id == ^id)
                  normalize_item_assets(reloaded_item.id, item_attrs["assets"] || %{})
                end
                
                # Update collection extent after item partial update
                if reloaded_item.collection_id do
                  update_collection_extent(reloaded_item.collection_id)
                end

                links = if Map.has_key?(params, "links") do
                  custom_links = Map.get(item_attrs, "links", reloaded_item.links || [])
                  DynamicLinkGenerator.generate_item_links(reloaded_item, custom_links)
                else
                  DynamicLinkGenerator.generate_item_links(reloaded_item, reloaded_item.links || [])
                end

                assets = reconstruct_item_assets(reloaded_item.id, reloaded_item.stac_extensions || [])

                item_response = %{
                  type: "Feature",
                  stac_version: reloaded_item.stac_version || "1.0.0",
                  stac_extensions: reloaded_item.stac_extensions || [],
                  id: reloaded_item.id,
                  geometry: reloaded_item.geometry,
                  bbox: reloaded_item.bbox,
                  properties: reloaded_item.properties || %{},
                  assets: assets,
                  collection: reloaded_item.collection_id,
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
        collection_id = item.collection_id
        case Repo.delete(item) do
            {:ok, _} ->
              # Update collection extent after item deletion
              if collection_id do
                update_collection_extent(collection_id)
              end
              
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
  List all items (filters out items from private catalogs if not authenticated)
  """
  def index(conn, params) do
    authenticated = conn.assigns[:authenticated] || false
    limit = min(parse_int(params["limit"] || "10"), 100)
    offset = parse_int(params["offset"] || "0")

    base_query = if authenticated do
      from i in Item
    else
      from i in Item,
        left_join: c in Collection, on: i.collection_id == c.id,
        left_join: cat in Catalog, on: c.catalog_id == cat.id,
        where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
    end
    
    query = from(i in base_query, limit: ^limit, offset: ^offset, order_by: [desc: i.datetime])
    items = Repo.all(query)
    
    count_query = if authenticated do
      from i in Item
    else
      from i in Item,
        left_join: c in Collection, on: i.collection_id == c.id,
        left_join: cat in Catalog, on: c.catalog_id == cat.id,
        where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
    end
    total_count = Repo.aggregate(count_query, :count, :id)

    items_with_links = Enum.map(items, fn item ->
      custom_links = item.links || []
      links = DynamicLinkGenerator.generate_item_links(item, custom_links)

      # Reconstruct assets from normalized data
      assets = reconstruct_item_assets(item.id, item.stac_extensions || [])

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

  @doc """
  Validate item params for PUT (full replacement - all required fields must be present)
  """
  defp validate_item_params_full(params, url_id) do
    # Use URL ID if body ID is not provided, otherwise validate they match
    body_id = params["id"]
    final_id = body_id || url_id
    
    if body_id && body_id != url_id do
      {:error, "Item ID in body (#{body_id}) does not match URL path ID (#{url_id})"}
    else
      collection_id = params["collection_id"] || params["collection"]
      
      required_fields = [
        {"type", params["type"]},
        {"geometry", params["geometry"]},
        {"properties", params["properties"]},
        {"collection_id", collection_id},
        {"stac_version", params["stac_version"]}
      ]
      
      missing_fields = Enum.filter(required_fields, fn {_field, value} -> is_nil(value) end)
                       |> Enum.map(fn {field, _} -> field end)

      if length(missing_fields) > 0 do
        {:error, "PUT requires all STAC fields for full replacement. Missing required fields: #{Enum.join(missing_fields, ", ")}"}
      else
        if params["type"] != "Feature" do
          {:error, "Invalid type. STAC items must have type: 'Feature'"}
        else
          if !Repo.get(Collection, collection_id) do
            {:error, "Referenced collection does not exist: #{collection_id}"}
          else
            geometry = parse_geometry(params["geometry"])

            item_attrs = %{
              "id" => final_id,
              "collection_id" => collection_id,
              "stac_version" => params["stac_version"],
              "stac_extensions" => params["stac_extensions"] || [],
              "geometry" => geometry,
              "bbox" => params["bbox"],
              "datetime" => parse_datetime(params["datetime"]),
              "properties" => params["properties"],
              "assets" => params["assets"] || %{},
              "links" => params["links"] || []
            }
            {:ok, item_attrs}
          end
        end
      end
    end
  end

  @doc """
  Validate item params for PATCH (partial update - only validate provided fields)
  """
  defp validate_item_params_partial(params) do
    # For PATCH, we validate only what's provided
    # Must have id, but other fields are optional
    if is_nil(params["id"]) do
      {:error, "Missing required field: id"}
    else
      collection_id = params["collection_id"] || params["collection"]
      
      # If collection_id is provided, validate it exists
      if collection_id && !Repo.get(Collection, collection_id) do
        {:error, "Referenced collection does not exist: #{collection_id}"}
      else
        geometry_value = if params["geometry"], do: parse_geometry(params["geometry"]), else: nil
        datetime_value = if params["datetime"], do: parse_datetime(params["datetime"]), else: nil
        
        item_attrs = %{}
        |> Map.put("id", params["id"])
        |> maybe_put("collection_id", collection_id)
        |> maybe_put("stac_version", params["stac_version"])
        |> maybe_put("stac_extensions", params["stac_extensions"])
        |> maybe_put("geometry", geometry_value)
        |> maybe_put("bbox", params["bbox"])
        |> maybe_put("datetime", datetime_value)
        |> maybe_put("properties", params["properties"])
        |> maybe_put("assets", params["assets"])
        |> maybe_put("links", params["links"])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{})

        {:ok, item_attrs}
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_item_params(params) do
    required_fields = ["id", "geometry"]
    missing_fields = Enum.filter(required_fields, &is_nil(params[&1]))

    if length(missing_fields) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      # Validate collection_id exists (handle both "collection_id" and "collection" fields)
      collection_id = params["collection_id"] || params["collection"]
      if is_nil(collection_id) do
        {:error, "Missing required field: collection_id or collection"}
      else
        if !Repo.get(Collection, collection_id) do
          {:error, "Referenced collection does not exist: #{collection_id}"}
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

  defp create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

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

  @doc """
  Replace entire item (PUT) - replaces all fields
  """
  defp replace_item(item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Partially update item (PATCH) - only updates provided fields
  """
  defp update_item_partial(item, attrs) do
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
  defp reconstruct_item_assets(item_id, stac_extensions \\ []) do
    assets = Repo.all(from a in ItemAsset, where: a.item_id == ^item_id)

    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = ItemAsset.to_stac_asset(asset, stac_extensions)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end

  @doc """
  Update collection extent based on items' geometries and datetime values.
  Calculates spatial extent using PostGIS: Box2D(ST_Envelope(st_extent(i.geometry::geometry)))
  and temporal extent from min/max datetime values.
  """
  defp update_collection_extent(collection_id) when is_binary(collection_id) do
    # Calculate spatial extent using PostGIS
    spatial_bbox_sql = """
    SELECT Box2D(ST_Envelope(st_extent(i.geometry::geometry)))::text as bbox
    FROM items i
    WHERE i.collection_id = $1
    AND i.geometry IS NOT NULL
    """

    # Calculate temporal extent
    temporal_sql = """
    SELECT 
      MIN(i.datetime) as min_datetime,
      MAX(i.datetime) as max_datetime
    FROM items i
    WHERE i.collection_id = $1
    AND i.datetime IS NOT NULL
    """

    case Repo.query(spatial_bbox_sql, [collection_id]) do
      {:ok, %{rows: [[bbox_string] | _]}} when is_binary(bbox_string) ->
        # Parse Box2D output: "BOX(minx miny, maxx maxy)"
        bbox_coords = parse_box2d(bbox_string)
        
        case Repo.query(temporal_sql, [collection_id]) do
          {:ok, %{rows: [[min_dt, max_dt] | _]}} ->
            temporal_interval = build_temporal_interval(min_dt, max_dt)
            extent = build_extent(bbox_coords, temporal_interval)
            update_collection_extent_field(collection_id, extent)
          
          {:ok, %{rows: []}} ->
            # No temporal data, only spatial
            extent = build_extent(bbox_coords, nil)
            update_collection_extent_field(collection_id, extent)
          
          _ ->
            # Error or no temporal data, use spatial only
            extent = build_extent(bbox_coords, nil)
            update_collection_extent_field(collection_id, extent)
        end

      {:ok, %{rows: []}} ->
        # No items with geometry, check if we have temporal data only
        case Repo.query(temporal_sql, [collection_id]) do
          {:ok, %{rows: [[min_dt, max_dt] | _]}} ->
            temporal_interval = build_temporal_interval(min_dt, max_dt)
            extent = build_extent(nil, temporal_interval)
            update_collection_extent_field(collection_id, extent)
          
          _ ->
            # No items at all, set extent to nil or empty
            update_collection_extent_field(collection_id, nil)
        end

      _ ->
        # Error in spatial query, try temporal only
        case Repo.query(temporal_sql, [collection_id]) do
          {:ok, %{rows: [[min_dt, max_dt] | _]}} ->
            temporal_interval = build_temporal_interval(min_dt, max_dt)
            extent = build_extent(nil, temporal_interval)
            update_collection_extent_field(collection_id, extent)
          
          _ ->
            :ok  # Silently fail if no data
        end
    end
  end

  defp update_collection_extent(_), do: :ok

  defp parse_box2d(box_string) when is_binary(box_string) do
    # Parse "BOX(minx miny, maxx maxy)" format
    case Regex.run(~r/BOX\(([\d\.\-]+)\s+([\d\.\-]+),\s+([\d\.\-]+)\s+([\d\.\-]+)\)/, box_string) do
      [_, minx, miny, maxx, maxy] ->
        try do
          [
            String.to_float(minx),
            String.to_float(miny),
            String.to_float(maxx),
            String.to_float(maxy)
          ]
        rescue
          _ -> nil
        end
      _ -> nil
    end
  end

  defp parse_box2d(_), do: nil

  defp build_temporal_interval(min_dt, max_dt) when not is_nil(min_dt) and not is_nil(max_dt) do
    min_str = DateTime.to_iso8601(min_dt)
    max_str = DateTime.to_iso8601(max_dt)
    [[min_str, max_str]]
  end

  defp build_temporal_interval(min_dt, _) when not is_nil(min_dt) do
    min_str = DateTime.to_iso8601(min_dt)
    [[min_str, nil]]
  end

  defp build_temporal_interval(_, max_dt) when not is_nil(max_dt) do
    max_str = DateTime.to_iso8601(max_dt)
    [[nil, max_str]]
  end

  defp build_temporal_interval(_, _), do: nil

  defp build_extent(nil, nil), do: nil
  defp build_extent(bbox_coords, nil) when is_list(bbox_coords) do
    %{"spatial" => %{"bbox" => [bbox_coords]}}
  end
  defp build_extent(nil, temporal_interval) when is_list(temporal_interval) do
    %{"temporal" => %{"interval" => temporal_interval}}
  end
  defp build_extent(bbox_coords, temporal_interval) when is_list(bbox_coords) and is_list(temporal_interval) do
    %{
      "spatial" => %{"bbox" => [bbox_coords]},
      "temporal" => %{"interval" => temporal_interval}
    }
  end
  defp build_extent(_, _), do: nil

  defp update_collection_extent_field(collection_id, extent) do
    case Repo.get(Collection, collection_id) do
      nil ->
        :ok  # Collection doesn't exist, skip

      collection ->
        changeset = Collection.changeset(collection, %{"extent" => extent})
        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, _} -> :ok  # Silently fail on update error
        end
    end
  end
end
