defmodule StacApi.Data.Search do
  @moduledoc """
  Database-powered STAC search functionality.
  """

  import Ecto.Query
  alias StacApi.Repo
  alias StacApi.Data.{Item, Collection, ItemAsset, Catalog, ItemFilters}
  alias StacApiWeb.{DynamicLinkGenerator, LinkResolver}

  def search(params \\ %{}, authenticated \\ false) do
    case ItemFilters.parse(params) do
      {:ok, filters} -> search(params, authenticated, filters)
      {:error, _, _} -> []
    end
  end

  def search(params, authenticated, filters) do
    query =
      Item
      |> build_search_query(params, authenticated, filters)
      |> apply_pagination(params)

    # Geometry is loaded like everywhere else (a Geo struct at full precision),
    # so /search renders it exactly as the collection item endpoints do.
    raw_results =
      query
      |> select([i], %{
        id: i.id,
        stac_version: i.stac_version,
        stac_extensions: i.stac_extensions,
        geometry: i.geometry,
        bbox: i.bbox,
        datetime: i.datetime,
        start_datetime: i.start_datetime,
        end_datetime: i.end_datetime,
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
      geometry: item_map.geometry,
      bbox: item_map.bbox,
      datetime: item_map.datetime,
      start_datetime: item_map.start_datetime,
      end_datetime: item_map.end_datetime,
      properties: item_map.properties,
      # Will be reconstructed from normalized data
      assets: %{},
      links: item_map.links,
      collection_id: item_map.collection_id,
      inserted_at: item_map.inserted_at,
      updated_at: item_map.updated_at
    }
  end

  def count_search_results(params \\ %{}, authenticated \\ false) do
    case ItemFilters.parse(params) do
      {:ok, filters} -> count_search_results(params, authenticated, filters)
      {:error, _, _} -> 0
    end
  end

  def count_search_results(params, authenticated, filters) do
    Item
    |> build_search_query(params, authenticated, filters)
    |> Repo.aggregate(:count, :id)
  end

  defp build_search_query(query, params, authenticated, filters) do
    query
    |> filter_by_private_catalogs(authenticated)
    |> filter_by_collections(params[:collections] || params["collections"])
    |> ItemFilters.apply(filters)
    |> filter_by_ids(params[:ids] || params["ids"])
    |> filter_by_intersects(params[:intersects] || params["intersects"])
    |> order_by([i], desc: i.datetime)
  end

  defp filter_by_private_catalogs(query, true), do: query

  defp filter_by_private_catalogs(query, false) do
    from(i in query,
      left_join: c in Collection,
      on: i.collection_id == c.id,
      left_join: cat in Catalog,
      on: c.catalog_id == cat.id,
      where: is_nil(c.catalog_id) or cat.private != true or is_nil(cat.private)
    )
  end

  defp filter_by_collections(query, nil), do: query

  defp filter_by_collections(query, collections) when is_binary(collections) do
    collection_list = String.split(collections, ",") |> Enum.map(&String.trim/1)
    filter_by_collections(query, collection_list)
  end

  defp filter_by_collections(query, collections) when is_list(collections) do
    from(i in query, where: i.collection_id in ^collections)
  end

  defp filter_by_ids(query, nil), do: query

  defp filter_by_ids(query, ids) when is_binary(ids) do
    id_list = String.split(ids, ",") |> Enum.map(&String.trim/1)
    filter_by_ids(query, id_list)
  end

  defp filter_by_ids(query, ids) when is_list(ids) do
    from(i in query, where: i.id in ^ids)
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
        from(i in query,
          where: fragment("ST_Intersects(?, ?::geography)", i.geometry, ^geo)
        )

      _ ->
        query
    end
  end

  defp filter_by_intersects(query, _), do: query

  @default_limit 10
  @max_limit 100

  @doc """
  The page size a search really gets, used for the query and for the paging
  links alike. Missing means #{@default_limit}; above #{@max_limit} returns
  #{@max_limit} (the spec asks for the maximum instead of an error); below 1 or
  not an integer is an error, which the API answers with 400.
  """
  @spec effective_limit(map()) :: {:ok, pos_integer()} | {:error, :limit, String.t()}
  def effective_limit(params) do
    case Map.get(params, "limit", Map.get(params, :limit)) do
      nil -> {:ok, @default_limit}
      "" -> {:ok, @default_limit}
      limit when is_integer(limit) -> check_limit(limit)
      limit when is_binary(limit) -> limit |> Integer.parse() |> check_limit()
      _ -> check_limit(:error)
    end
  end

  defp check_limit({limit, ""}), do: check_limit(limit)
  defp check_limit(limit) when is_integer(limit) and limit >= 1, do: {:ok, min(limit, @max_limit)}
  defp check_limit(_), do: {:error, :limit, "must be an integer of at least 1"}

  defp apply_pagination(query, params) do
    # The API validates limit before searching; other callers get the default.
    limit =
      case effective_limit(params) do
        {:ok, limit} -> limit
        {:error, _, _} -> @default_limit
      end

    offset = parse_int(params[:offset] || params["offset"] || "0")

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp preload_collections(items) do
    Repo.preload(items, :collection)
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0

  @doc """
  The public STAC Item, the one shape returned by `/search`,
  `/collections/:id/items` and `/collections/:id/items/:item_id`.

  `properties` come back as stored: `datetime`, `start_datetime` and
  `end_datetime` are normalised at write time, so they are not rendered again
  from the typed columns, and there is no top-level `datetime`. Links are the
  generated `self` / `root` / `parent` / `collection` links plus the stored ones.
  """
  def serialize_item_for_api(%Item{} = item) do
    # Reconstruct assets from normalized data
    assets = reconstruct_item_assets(item.id, item.stac_extensions || [])
    stored_links = item.links |> serialize_links() |> LinkResolver.resolve_links()

    %{
      "type" => "Feature",
      "stac_version" => item.stac_version,
      "stac_extensions" => item.stac_extensions || [],
      "id" => item.id,
      "geometry" => item.geometry |> serialize_geometry(),
      "bbox" => item.bbox |> serialize_bbox(),
      "properties" => item.properties |> serialize_properties(),
      "collection" => item.collection_id,
      "assets" => assets |> serialize_assets(),
      "links" => DynamicLinkGenerator.generate_item_links(item, stored_links)
    }
  end

  defp serialize_geometry(nil), do: nil

  defp serialize_geometry(%Geo.Point{coordinates: {x, y}}),
    do: %{"type" => "Point", "coordinates" => [x, y]}

  defp serialize_geometry(%Geo.Point{coordinates: {x, y, z}}),
    do: %{"type" => "Point", "coordinates" => [x, y, z]}

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

  defp serialize_bbox(nil), do: nil
  defp serialize_bbox(bbox) when is_list(bbox), do: bbox

  defp serialize_bbox({minx, miny, maxx, maxy}) when is_number(minx) do
    [minx, miny, maxx, maxy]
  end

  defp serialize_bbox(bbox), do: bbox

  defp serialize_properties(properties) when is_map(properties),
    do: deep_serialize_tuples(properties)

  defp serialize_properties(_properties), do: %{}

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

  defp deep_serialize_tuples({x, y, z, w})
       when is_number(x) and is_number(y) and is_number(z) and is_number(w) do
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

  # Reconstruct assets for multiple items efficiently
  defp reconstruct_assets_for_items(items) do
    item_ids = Enum.map(items, & &1.id)

    # Get all assets for these items in one query
    assets_query = from(a in ItemAsset, where: a.item_id in ^item_ids)
    all_assets = Repo.all(assets_query)

    # Group assets by item_id
    assets_by_item = Enum.group_by(all_assets, & &1.item_id)

    # Update each item with its assets
    Enum.map(items, fn item ->
      item_assets = Map.get(assets_by_item, item.id, [])

      reconstructed_assets =
        Enum.reduce(item_assets, %{}, fn asset, acc ->
          asset_data = ItemAsset.to_stac_asset(asset, item.stac_extensions || [])
          Map.put(acc, asset.asset_key, asset_data)
        end)

      %{item | assets: reconstructed_assets}
    end)
  end

  # Reconstruct assets from normalized table back to STAC format for a single item
  defp reconstruct_item_assets(item_id, stac_extensions) do
    assets = Repo.all(from(a in ItemAsset, where: a.item_id == ^item_id))

    Enum.reduce(assets, %{}, fn asset, acc ->
      asset_data = ItemAsset.to_stac_asset(asset, stac_extensions)
      Map.put(acc, asset.asset_key, asset_data)
    end)
  end
end
