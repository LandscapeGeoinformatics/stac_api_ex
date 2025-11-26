defmodule StacApi.Data.Search do
  @moduledoc """
  Database-powered STAC search functionality.
  """

  import Ecto.Query
  alias StacApi.Repo
  alias StacApi.Data.{Item, Collection, ItemAsset, Catalog}

  def search(params \\ %{}, authenticated \\ false) do
  query =
    Item
    |> build_search_query(params, authenticated)
    |> apply_pagination(params)

  # First get the raw results with geometry as GeoJSON
  raw_results =
    query
    |> select([i], %{
      id: i.id,
      stac_version: i.stac_version,
      stac_extensions: i.stac_extensions,
      geometry: fragment("ST_AsGeoJSON(?::geometry) as geometry", i.geometry),
      bbox: i.bbox,
      datetime: i.datetime,
      properties: i.properties,
      assets: i.assets,
      links: i.links,
      collection_id: i.collection_id,
      inserted_at: i.inserted_at,
      updated_at: i.updated_at
    })
    |> Repo.all()

  # Then convert to proper Item structs
  raw_results
  |> Enum.map(&convert_to_item_struct/1)
  |> preload_collections()
  |> reconstruct_assets_for_items()
end

defp convert_to_item_struct(item_map) do
  %Item{
    id: item_map.id,
    stac_version: item_map.stac_version,
    stac_extensions: item_map.stac_extensions,
    geometry: parse_geometry(item_map.geometry),
    bbox: item_map.bbox,
    datetime: item_map.datetime,
    properties: item_map.properties,
    assets: %{},  # Will be reconstructed from normalized data
    links: item_map.links,
    collection_id: item_map.collection_id,
    inserted_at: item_map.inserted_at,
    updated_at: item_map.updated_at
  }
end

defp parse_geometry(nil), do: nil
defp parse_geometry(geojson_string) when is_binary(geojson_string) do
  case Jason.decode(geojson_string) do
    {:ok, geojson_map} ->
      case Geo.JSON.decode(geojson_map) do
        {:ok, geo_struct} -> geo_struct
        _ -> geojson_map
      end
    _ -> nil
  end
end
defp parse_geometry(geometry), do: geometry

defp convert_geojson_geometry(%{geometry: geojson_string} = item) when is_binary(geojson_string) do
  case Jason.decode(geojson_string) do
    {:ok, geometry} ->
      case Geo.JSON.decode(geometry) do
        {:ok, geo_struct} -> Map.put(item, :geometry, geo_struct)
        _ -> Map.put(item, :geometry, geometry)
      end
    {:error, _} -> Map.put(item, :geometry, nil)
  end
end
defp convert_geojson_geometry(item), do: item



  def count_search_results(params \\ %{}, authenticated \\ false) do
    Item
    |> build_search_query(params, authenticated)
    |> Repo.aggregate(:count, :id)
  end

  defp build_search_query(query, params, authenticated) do
    query
    |> filter_by_private_catalogs(authenticated)
    |> filter_by_collections(params[:collections] || params["collections"])
    |> filter_by_bbox(params[:bbox] || params["bbox"])
    |> filter_by_datetime(params[:datetime] || params["datetime"])
    |> filter_by_ids(params[:ids] || params["ids"])
    |> filter_by_intersects(params[:intersects] || params["intersects"])
    |> order_by([i], desc: i.datetime)
  end

  defp filter_by_private_catalogs(query, true), do: query
  defp filter_by_private_catalogs(query, false) do
    from i in query,
      left_join: c in Collection, on: i.collection_id == c.id,
      left_join: cat in Catalog, on: c.catalog_id == cat.id,
      where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
  end

  defp filter_by_collections(query, nil), do: query
  defp filter_by_collections(query, collections) when is_binary(collections) do
    collection_list = String.split(collections, ",") |> Enum.map(&String.trim/1)
    filter_by_collections(query, collection_list)
  end
  defp filter_by_collections(query, collections) when is_list(collections) do
    from i in query, where: i.collection_id in ^collections
  end

  defp filter_by_bbox(query, nil), do: query
  defp filter_by_bbox(query, bbox) when is_binary(bbox) do
    case String.split(bbox, ",") |> Enum.map(&parse_float/1) do
      [minx, miny, maxx, maxy] when is_number(minx) and is_number(miny) and
                                   is_number(maxx) and is_number(maxy) ->
        filter_by_bbox_coords(query, minx, miny, maxx, maxy)
      _ -> query
    end
  end
  defp filter_by_bbox(query, [minx, miny, maxx, maxy]) when is_number(minx) do
    filter_by_bbox_coords(query, minx, miny, maxx, maxy)
  end
  defp filter_by_bbox(query, _), do: query

  defp filter_by_bbox_coords(query, minx, miny, maxx, maxy) do
    # Create a bounding box polygon in WKT format
    bbox_wkt = "POLYGON((#{minx} #{miny}, #{maxx} #{miny}, #{maxx} #{maxy}, #{minx} #{maxy}, #{minx} #{miny}))"

    from i in query,
      where: fragment("ST_Intersects(?, ST_GeomFromText(?, 4326)::geography)", i.geometry, ^bbox_wkt)
  end

  defp filter_by_datetime(query, nil), do: query
  defp filter_by_datetime(query, datetime) when is_binary(datetime) do
    case String.split(datetime, "/") do
      [start_str, end_str] ->
        start_dt = parse_datetime(start_str)
        end_dt = parse_datetime(end_str)
        filter_by_datetime_range(query, start_dt, end_dt)
      [single] ->
        single_dt = parse_datetime(single)
        if single_dt do
          from i in query, where: i.datetime == ^single_dt
        else
          query
        end
      _ -> query
    end
  end
  defp filter_by_datetime(query, _), do: query

  defp filter_by_datetime_range(query, start_dt, end_dt) do
    cond do
      start_dt && end_dt ->
        from i in query, where: i.datetime >= ^start_dt and i.datetime <= ^end_dt
      start_dt ->
        from i in query, where: i.datetime >= ^start_dt
      end_dt ->
        from i in query, where: i.datetime <= ^end_dt
      true -> query
    end
  end

  defp filter_by_ids(query, nil), do: query
  defp filter_by_ids(query, ids) when is_binary(ids) do
    id_list = String.split(ids, ",") |> Enum.map(&String.trim/1)
    filter_by_ids(query, id_list)
  end
  defp filter_by_ids(query, ids) when is_list(ids) do
    from i in query, where: i.id in ^ids
  end

  defp filter_by_intersects(query, nil), do: query
  defp filter_by_intersects(query, geojson) when is_binary(geojson) do
    try do
      geometry = Jason.decode!(geojson)
      filter_by_intersects(query, geometry)
    rescue
      _ -> query
    end
  end
  defp filter_by_intersects(query, %{"type" => _, "coordinates" => _} = geojson) do
    case Geo.JSON.decode(geojson) do
      {:ok, geo} ->
        from i in query,
          where: fragment("ST_Intersects(?, ?::geography)", i.geometry, ^geo)
      _ -> query
    end
  end
  defp filter_by_intersects(query, _), do: query

  defp apply_pagination(query, params) do
    limit = min(parse_int(params[:limit] || params["limit"] || "10"), 100)
    offset = parse_int(params[:offset] || params["offset"] || "0")

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp preload_collections(items) do
    Repo.preload(items, :collection)
  end

  # Helper functions
  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end
  defp parse_float(num) when is_number(num), do: num
  defp parse_float(_), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0

  defp parse_datetime(""), do: nil
  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
  defp parse_datetime(_), do: nil

  def serialize_item_for_api(%Item{} = item) do
  # Reconstruct assets from normalized data
  assets = reconstruct_item_assets(item.id, item.stac_extensions || [])
  
  %{
    "type" => "Feature",
    "stac_version" => item.stac_version,
    "stac_extensions" => item.stac_extensions || [],
    "id" => item.id,
    "geometry" => item.geometry |> serialize_geometry(),
    "bbox" => item.bbox |> serialize_bbox(),
    "properties" => item.properties |> serialize_properties(item.datetime),
    "collection" => item.collection_id,
    "assets" => assets |> serialize_assets(),
    "links" => item.links |> serialize_links()
  }
end

defp serialize_geometry(nil), do: nil
defp serialize_geometry(%Geo.Point{coordinates: {x, y}}), do: %{"type" => "Point", "coordinates" => [x, y]}
defp serialize_geometry(%Geo.Point{coordinates: {x, y, z}}), do: %{"type" => "Point", "coordinates" => [x, y, z]}
defp serialize_geometry(%Geo.Polygon{coordinates: coords}) do
  %{"type" => "Polygon", "coordinates" => convert_coords(coords)}
end
defp serialize_geometry(%Geo.MultiPolygon{coordinates: coords}) do
  %{"type" => "MultiPolygon", "coordinates" => convert_coords(coords)}
end

defp serialize_geometry(%{"type" => _, "coordinates" => _} = geojson), do: geojson
defp serialize_geometry(geometry) when is_map(geometry), do: geometry
defp serialize_geometry(_), do: nil

defp convert_coords(coords) when is_list(coords) do
  Enum.map(coords, fn
    {x, y} -> [x, y]
    {x, y, z} -> [x, y, z]
    list when is_list(list) -> convert_coords(list)
    other -> other
  end)
end
defp convert_coords(other), do: other

  defp serialize_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end
  defp serialize_datetime(_), do: nil

  defp serialize_bbox(nil), do: nil
  defp serialize_bbox(bbox) when is_list(bbox), do: bbox
  defp serialize_bbox({minx, miny, maxx, maxy}) when is_number(minx) do
    [minx, miny, maxx, maxy]
  end
  defp serialize_bbox(bbox), do: bbox

  defp serialize_properties(nil, datetime), do: %{"datetime" => serialize_datetime(datetime)}
  defp serialize_properties(properties, datetime) when is_map(properties) do
    properties
    |> deep_serialize_tuples()
    |> Map.put("datetime", serialize_datetime(datetime))
  end
  defp serialize_properties(properties, datetime), do: %{"datetime" => serialize_datetime(datetime)}

  defp serialize_assets(nil), do: %{}
  defp serialize_assets(assets) when is_map(assets) do
    deep_serialize_tuples(assets)
  end
  defp serialize_assets(_), do: %{}

  defp serialize_links(nil), do: []
  defp serialize_links(links) when is_list(links) do
    Enum.map(links, &deep_serialize_tuples/1)
  end
  defp serialize_links(_), do: []

  defp deep_serialize_tuples({x, y}) when is_number(x) and is_number(y) do
    [x, y]
  end
  defp deep_serialize_tuples({x, y, z}) when is_number(x) and is_number(y) and is_number(z) do
    [x, y, z]
  end
  defp deep_serialize_tuples({x, y, z, w}) when is_number(x) and is_number(y) and is_number(z) and is_number(w) do
    [x, y, z, w]
  end
  # Handle Decimal structs
  defp deep_serialize_tuples(%Decimal{} = decimal) do
    Decimal.to_float(decimal)
  end
  defp deep_serialize_tuples(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, deep_serialize_tuples(v)} end)
  end
  defp deep_serialize_tuples(list) when is_list(list) do
    Enum.map(list, &deep_serialize_tuples/1)
  end
  defp deep_serialize_tuples(value), do: value

  @doc """
  Reconstruct assets for multiple items efficiently
  """
  defp reconstruct_assets_for_items(items) do
    item_ids = Enum.map(items, & &1.id)
    
    # Get all assets for these items in one query
    assets_query = from a in ItemAsset, where: a.item_id in ^item_ids
    all_assets = Repo.all(assets_query)
    
    # Group assets by item_id
    assets_by_item = Enum.group_by(all_assets, & &1.item_id)
    
    # Update each item with its assets
    Enum.map(items, fn item ->
      item_assets = Map.get(assets_by_item, item.id, [])
      reconstructed_assets = Enum.reduce(item_assets, %{}, fn asset, acc ->
        asset_data = ItemAsset.to_stac_asset(asset, item.stac_extensions || [])
        Map.put(acc, asset.asset_key, asset_data)
      end)
      
      %{item | assets: reconstructed_assets}
    end)
  end

  @doc """
  Reconstruct assets from normalized table back to STAC format for a single item
  """
  defp reconstruct_item_assets(item_id, stac_extensions \\ []) do
    assets = Repo.all(from a in ItemAsset, where: a.item_id == ^item_id)
    
    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = ItemAsset.to_stac_asset(asset, stac_extensions)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end
end
