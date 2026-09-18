defmodule StacApiWeb.StacBrowserHelpers do
  @moduledoc """
  Helper functions for STAC browser functionality
  """

  @doc """
  Validates if a JSON file is a valid STAC item or collection
  """
  def validate_stac_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            validate_stac_json(json_data)

          {:error, _} ->
            {:error, "Invalid JSON"}
        end

      {:error, reason} ->
        {:error, "Cannot read file: #{reason}"}
    end
  end

  defp validate_stac_json(%{"type" => "Feature", "stac_version" => _version}) do
    {:ok, :item}
  end

  defp validate_stac_json(%{"type" => "Collection", "stac_version" => _version}) do
    {:ok, :collection}
  end

  defp validate_stac_json(%{"type" => "Catalog", "stac_version" => _version}) do
    {:ok, :catalog}
  end

  defp validate_stac_json(_) do
    {:error, "Not a valid STAC file"}
  end

  @doc """
  Extract metadata from STAC files for display
  """
  def extract_stac_metadata(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            extract_metadata_from_json(json_data)

          {:error, _} ->
            %{}
        end

      {:error, _} ->
        %{}
    end
  end

  defp extract_metadata_from_json(%{"type" => "Feature"} = item) do
    %{
      id: Map.get(item, "id"),
      collection: Map.get(item, "collection"),
      datetime: get_in(item, ["properties", "datetime"]),
      bbox: Map.get(item, "bbox"),
      assets_count: map_size(Map.get(item, "assets", %{}))
    }
  end

  defp extract_metadata_from_json(%{"type" => "Collection"} = collection) do
    %{
      id: Map.get(collection, "id"),
      title: Map.get(collection, "title"),
      description: Map.get(collection, "description"),
      license: Map.get(collection, "license"),
      extent: Map.get(collection, "extent")
    }
  end

  defp extract_metadata_from_json(%{"type" => "Catalog"} = catalog) do
    %{
      id: Map.get(catalog, "id"),
      title: Map.get(catalog, "title"),
      description: Map.get(catalog, "description"),
      links_count: length(Map.get(catalog, "links", []))
    }
  end

  defp extract_metadata_from_json(_), do: %{}

  @doc """
  Generate API URLs for collections and items
  """
  def get_api_urls(collection_path, item_id \\ nil) do
    base_url = StacApiWeb.Endpoint.url()

    urls = %{
      collection: "#{base_url}/stac/collections/#{collection_path}",
      items: "#{base_url}/stac/collections/#{collection_path}/items"
    }

    if item_id do
      Map.put(urls, :item, "#{base_url}/stac/collections/#{collection_path}/items/#{item_id}")
    else
      urls
    end
  end

  @doc """
  Check if directory contains STAC files
  """
  def contains_stac_files?(directory_path) do
    case File.ls(directory_path) do
      {:ok, files} ->
        files
        |> Enum.any?(fn file ->
          String.ends_with?(file, ".json") and
            File.regular?(Path.join(directory_path, file))
        end)

      {:error, _} ->
        false
    end
  end

  @doc """
  Get STAC file count in directory
  """
  def count_stac_files(directory_path) do
    case File.ls(directory_path) do
      {:ok, files} ->
        files
        |> Enum.count(fn file ->
          file_path = Path.join(directory_path, file)
          String.ends_with?(file, ".json") and File.regular?(file_path)
        end)

      {:error, _} ->
        0
    end
  end

  @doc """
  Extracts the parent path of a given path
  """
  def get_parent_path(path) do
    Path.dirname(path)
  end

  def type_badge_class(type) do
    case type do
      "Item" -> "bg-secondary text-white"
      "Asset" -> "bg-primary text-secondary"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  # Search result helpers
  def get_item_id(%{id: id}), do: id
  def get_item_id(%{"id" => id}), do: id
  def get_item_id(item) when is_map(item), do: Map.get(item, :id) || Map.get(item, "id")
  def get_item_id(_), do: "Unknown"

  def get_collection_id(%{collection_id: id}), do: id
  def get_collection_id(%{"collection_id" => id}), do: id

  def get_collection_id(item) when is_map(item),
    do: Map.get(item, :collection_id) || Map.get(item, "collection_id")

  def get_collection_id(_), do: nil

  def get_datetime(%{datetime: dt}), do: dt
  def get_datetime(%{"datetime" => dt}), do: dt

  def get_datetime(item) when is_map(item),
    do: Map.get(item, :datetime) || Map.get(item, "datetime")

  def get_datetime(_), do: nil

  def get_bbox(%{bbox: bbox}), do: bbox
  def get_bbox(%{"bbox" => bbox}), do: bbox
  def get_bbox(item) when is_map(item), do: Map.get(item, :bbox) || Map.get(item, "bbox")
  def get_bbox(_), do: nil

  def get_properties(%{properties: props}), do: props
  def get_properties(%{"properties" => props}), do: props

  def get_properties(item) when is_map(item),
    do: Map.get(item, :properties) || Map.get(item, "properties")

  def get_properties(_), do: nil

  def get_assets(%{assets: assets}), do: assets
  def get_assets(%{"assets" => assets}), do: assets
  def get_assets(item) when is_map(item), do: Map.get(item, :assets) || Map.get(item, "assets")
  def get_assets(_), do: nil

  def get_bbox_value(search_params, index) do
    case search_params["bbox"] do
      bbox_string when is_binary(bbox_string) ->
        bbox_parts = String.split(bbox_string, ",")

        if length(bbox_parts) > index do
          Enum.at(bbox_parts, index)
        else
          ""
        end

      _ ->
        ""
    end
  end

  # ---------------------------------------------------------------------------
  # Rendering helpers for the STAC browser templates and components.
  #
  # Every function below is total: it accepts nil or wrongly typed input and
  # returns a safe default, so a missing or malformed JSON element never
  # crashes a page. Property maps use string keys (they come from JSON);
  # Ecto structs are also accepted where noted.
  # ---------------------------------------------------------------------------

  @core_property_keys ~w(title description created updated gsd platform instruments constellation mission license datetime start_datetime end_datetime)
  @prefix_order ~w(proj raster eo table vector sci file lgeo sat view processing)

  @doc """
  Derives the temporal coverage from an item or its properties.

  Accepts a properties map (string keys), an `%Item{}` struct, or the item map
  built in the browser controller (atom keys plus a `properties` map). Returns
  `{:instant, %DateTime{}}`, `{:range, start_or_nil, end_or_nil}` or `:none`.
  """
  def temporal_range(src) when is_map(src) do
    dt = fetch_temporal(src, "datetime")
    start_dt = fetch_temporal(src, "start_datetime")
    end_dt = fetch_temporal(src, "end_datetime")

    case {dt, start_dt, end_dt} do
      {%DateTime{} = d, _, _} -> {:instant, d}
      {_, nil, nil} -> :none
      {_, s, e} -> {:range, s, e}
    end
  end

  def temporal_range(_), do: :none

  defp fetch_temporal(src, key) do
    atom_key = String.to_existing_atom(key)
    props = Map.get(src, "properties") || Map.get(src, :properties) || %{}
    props = if is_map(props), do: props, else: %{}

    [Map.get(src, atom_key), Map.get(src, key), Map.get(props, key)]
    |> Enum.map(&parse_datetime/1)
    |> Enum.find(&(&1 != nil))
  end

  @doc """
  Parses ISO 8601 strings, `DateTime`, `NaiveDateTime` or `Date` into a UTC
  `DateTime`. Anything else becomes nil.
  """
  def parse_datetime(%DateTime{} = dt), do: dt
  def parse_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  def parse_datetime(%Date{} = d), do: DateTime.new!(d, ~T[00:00:00], "Etc/UTC")

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        case Date.from_iso8601(str) do
          {:ok, d} -> parse_datetime(d)
          _ -> nil
        end
    end
  end

  def parse_datetime(_), do: nil

  @doc """
  Formats a datetime as `2017-09-01` (`:date`) or `2017-09-01 00:00 UTC`
  (`:datetime`). Returns `"n/a"` when the value cannot be parsed.
  """
  def format_dt(value, style \\ :date)

  def format_dt(value, style) do
    case parse_datetime(value) do
      nil ->
        "n/a"

      dt ->
        Calendar.strftime(dt, if(style == :datetime, do: "%Y-%m-%d %H:%M UTC", else: "%Y-%m-%d"))
    end
  end

  @doc "Whole days covered by a `{:range, start, end}` tuple, or nil."
  def duration_days({:range, %DateTime{} = s, %DateTime{} = e}) do
    days = div(DateTime.diff(e, s, :second), 86_400)
    if days >= 0, do: days + 1, else: nil
  end

  def duration_days(_), do: nil

  @doc "Human readable byte size, e.g. `847.8 MB`. Returns `\"n/a\"` for non-numbers."
  def format_bytes(n) when is_number(n) and n >= 0 do
    cond do
      n >= 1_000_000_000_000 -> "#{round1(n / 1_000_000_000_000)} TB"
      n >= 1_000_000_000 -> "#{round1(n / 1_000_000_000)} GB"
      n >= 1_000_000 -> "#{round1(n / 1_000_000)} MB"
      n >= 1_000 -> "#{round1(n / 1_000)} kB"
      true -> "#{trunc(n)} B"
    end
  end

  def format_bytes(_), do: "n/a"

  defp round1(f), do: :erlang.float_to_binary(f * 1.0, decimals: 1)

  @doc "Integer with thousands separators, e.g. `4,496,422`."
  def format_int(n) when is_integer(n) do
    n
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> then(&if(n < 0, do: "-" <> &1, else: &1))
  end

  def format_int(f) when is_float(f), do: format_int(round(f))
  def format_int(_), do: "n/a"

  @doc "Compact coordinate formatting: floats rounded to 6 decimals, ints untouched."
  def format_coord(f) when is_float(f), do: to_string(Float.round(f, 6))
  def format_coord(i) when is_integer(i), do: Integer.to_string(i)
  def format_coord(other), do: to_string(other)

  @doc ~S"""
  Turns a STAC key into a label: `"proj:bbox"` → `"Bbox"`, `"start_datetime"` →
  `"Start datetime"`.
  """
  def humanize_key(key) when is_binary(key) do
    key
    |> String.split(":", parts: 2)
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def humanize_key(key), do: humanize_key(to_string(key))

  @doc "Short label for a media type, full string kept for tooltips."
  def media_type_label(nil), do: "unknown"

  def media_type_label(type) when is_binary(type) do
    t = String.downcase(type)

    cond do
      String.contains?(t, "cloud-optimized") -> "COG GeoTIFF"
      String.contains?(t, "image/tiff") -> "GeoTIFF"
      String.contains?(t, "image/jp2") -> "JPEG 2000"
      String.contains?(t, "flatgeobuf") -> "FlatGeobuf"
      String.contains?(t, "geopackage") -> "GeoPackage"
      String.contains?(t, "parquet") -> "GeoParquet"
      String.contains?(t, "shapefile") or String.contains?(t, "x-shapefile") -> "Shapefile"
      String.contains?(t, "geo+json") -> "GeoJSON"
      String.contains?(t, "json") -> "JSON"
      String.contains?(t, "netcdf") -> "NetCDF"
      String.contains?(t, "hdf") -> "HDF"
      String.contains?(t, "zarr") -> "Zarr"
      String.contains?(t, "copc") -> "COPC"
      String.contains?(t, "laszip") or String.contains?(t, "vnd.las") -> "LAS/LAZ"
      String.contains?(t, "image/png") -> "PNG"
      String.contains?(t, "image/jpeg") -> "JPEG"
      String.contains?(t, "image/webp") -> "WebP"
      String.contains?(t, "xml") -> "XML"
      String.contains?(t, "text/html") -> "HTML"
      String.contains?(t, "text/csv") -> "CSV"
      String.contains?(t, "text/plain") -> "Text"
      String.contains?(t, "pdf") -> "PDF"
      String.contains?(t, "zip") -> "ZIP"
      String.length(type) > 24 -> String.slice(type, 0, 22) <> "…"
      true -> type
    end
  end

  def media_type_label(other), do: media_type_label(to_string(other))

  @doc "Classifies an asset as `:raster`, `:vector`, `:table` or `:other`."
  def asset_kind(asset) when is_map(asset) do
    t = asset |> Map.get("type") |> to_string_safe() |> String.downcase()

    cond do
      Map.has_key?(asset, "raster:bands") ->
        :raster

      contains_any?(t, ~w(image/tiff image/jp2 netcdf hdf zarr)) ->
        :raster

      contains_any?(t, ~w(flatgeobuf geopackage geo+json shapefile vnd.geo copc laszip)) ->
        :vector

      contains_any?(t, ~w(parquet csv arrow feather)) ->
        :table

      Enum.any?(Map.keys(asset), &String.starts_with?(to_string(&1), "vector:")) ->
        :vector

      Enum.any?(Map.keys(asset), &String.starts_with?(to_string(&1), "table:")) ->
        :table

      true ->
        :other
    end
  end

  def asset_kind(_), do: :other

  @doc """
  Classifies an item by its assets: `:raster`, `:raster_multi`, `:vector`,
  `:table` or `:other`.
  """
  def item_kind(assets) when is_map(assets) and map_size(assets) > 0 do
    kinds = assets |> Map.values() |> Enum.map(&asset_kind/1)
    raster_count = Enum.count(kinds, &(&1 == :raster))

    cond do
      raster_count > 1 -> :raster_multi
      raster_count == 1 -> :raster
      :vector in kinds -> :vector
      :table in kinds -> :table
      true -> :other
    end
  end

  def item_kind(%{assets: assets}), do: item_kind(assets)
  def item_kind(_), do: :other

  @doc "Display label for an item kind, e.g. `Raster · 6 assets`."
  def item_kind_label(kind, assets) do
    n = if is_map(assets), do: map_size(assets), else: 0
    noun = if n == 1, do: "asset", else: "assets"

    base =
      case kind do
        :raster -> "Raster"
        :raster_multi -> "Raster statistics"
        :vector -> "Vector"
        :table -> "Table"
        _ -> "Item"
      end

    "#{base} · #{n} #{noun}"
  end

  @doc "Emoji icon per asset/item kind."
  def kind_icon(:raster), do: "🗺️"
  def kind_icon(:raster_multi), do: "🗺️"
  def kind_icon(:vector), do: "🧭"
  def kind_icon(:table), do: "📊"
  def kind_icon(_), do: "📎"

  @doc """
  Sorts assets into `{primary, auxiliary}` lists of `{key, asset}` tuples.

  Primary assets carry the `data` role (or no roles at all); auxiliary ones are
  statistics, metadata, thumbnails and the like. Within a group, assets are
  ordered by role priority, then key.
  """
  def split_assets(assets) when is_map(assets) do
    assets
    |> Enum.map(fn {k, a} -> {to_string(k), if(is_map(a), do: a, else: %{})} end)
    |> Enum.sort_by(fn {k, a} -> {role_priority(a), k} end)
    |> Enum.split_with(fn {_k, a} -> primary_asset?(a) end)
  end

  def split_assets(_), do: {[], []}

  defp primary_asset?(asset) do
    roles = asset_roles(asset)
    roles == [] or "data" in roles
  end

  defp role_priority(asset) do
    roles = asset_roles(asset)

    cond do
      "data" in roles and not Enum.any?(roles, &(&1 in ["statistics", "metadata"])) -> 0
      "data" in roles -> 1
      "statistics" in roles -> 2
      "metadata" in roles -> 3
      Enum.any?(roles, &(&1 in ["thumbnail", "overview", "visual"])) -> 4
      true -> 5
    end
  end

  @doc "Roles of an asset as a list of strings (never nil)."
  def asset_roles(asset) when is_map(asset) do
    case Map.get(asset, "roles") do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  def asset_roles(_), do: []

  @doc "Grid columns for a list of assets: 1, 2 or 3."
  def asset_columns(assets) when is_list(assets), do: min(max(length(assets), 1), 3)
  def asset_columns(_), do: 1

  @doc "Label for an auxiliary asset group."
  def auxiliary_group_label(assets) when is_list(assets) do
    all_stats =
      Enum.all?(assets, fn {_k, a} ->
        roles = asset_roles(a)
        roles != [] and Enum.all?(roles, &(&1 in ["statistics", "metadata"]))
      end)

    if all_stats, do: "Statistics & metadata", else: "Auxiliary assets"
  end

  @doc "`raster:bands` of an asset as a list of maps (never nil)."
  def raster_bands(asset) when is_map(asset) do
    case Map.get(asset, "raster:bands") do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  def raster_bands(_), do: []

  @doc "Reads a raster band field, accepting raster v1 (`nodata`) and v2 (`raster:nodata`) keys."
  def band_field(band, name) when is_map(band) do
    Map.get(band, "raster:" <> name) || Map.get(band, name)
  end

  def band_field(_, _), do: nil

  @doc "Alternate hrefs of an asset as `[{name, href, type}]`."
  def asset_alternates(asset) when is_map(asset) do
    case Map.get(asset, "alternate") do
      alt when is_map(alt) ->
        alt
        |> Enum.flat_map(fn
          {name, %{"href" => href} = a} when is_binary(href) ->
            [{to_string(name), href, Map.get(a, "type")}]

          _ ->
            []
        end)
        |> Enum.sort_by(&elem(&1, 0))

      _ ->
        []
    end
  end

  def asset_alternates(_), do: []

  @asset_known_keys ~w(href type title description roles file:size alternate raster:bands)

  @doc "Asset keys not rendered by the dedicated parts of the asset card."
  def asset_extra(asset) when is_map(asset) do
    asset
    |> Enum.reject(fn {k, _} -> to_string(k) in @asset_known_keys end)
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def asset_extra(_), do: []

  @doc "True for http(s) URLs."
  def url?(str) when is_binary(str), do: String.match?(str, ~r{\Ahttps?://\S+\z})
  def url?(_), do: false

  @doc """
  Groups item properties for display.

  Returns `[{group_label, [{key, value}]}]`: `Core` first, then known extension
  prefixes in a fixed order, then unknown prefixes alphabetically, then
  unprefixed leftovers under `Other`. Keys in `opts[:skip]` are dropped. Empty
  groups are omitted.
  """
  def group_properties(props, opts \\ [])

  def group_properties(props, opts) when is_map(props) do
    skip = Keyword.get(opts, :skip, [])

    entries =
      props
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.reject(fn {k, _} -> k in skip end)
      |> Enum.sort_by(&elem(&1, 0))

    {core, rest} = Enum.split_with(entries, fn {k, _} -> k in @core_property_keys end)
    core = Enum.sort_by(core, fn {k, _} -> Enum.find_index(@core_property_keys, &(&1 == k)) end)

    {prefixed, plain} = Enum.split_with(rest, fn {k, _} -> String.contains?(k, ":") end)
    by_prefix = Enum.group_by(prefixed, fn {k, _} -> k |> String.split(":", parts: 2) |> hd() end)

    known =
      for p <- @prefix_order, Map.has_key?(by_prefix, p), do: {prefix_label(p), by_prefix[p]}

    unknown =
      by_prefix
      |> Map.keys()
      |> Enum.reject(&(&1 in @prefix_order))
      |> Enum.sort()
      |> Enum.map(&{prefix_label(&1), by_prefix[&1]})

    ([{"Core", core}] ++ known ++ unknown ++ [{"Other", plain}])
    |> Enum.reject(fn {_, list} -> list == [] end)
  end

  def group_properties(_, _), do: []

  @doc "Human label for a STAC extension prefix."
  def prefix_label("proj"), do: "Projection"
  def prefix_label("raster"), do: "Raster"
  def prefix_label("eo"), do: "Electro-optical"
  def prefix_label("table"), do: "Table"
  def prefix_label("vector"), do: "Vector"
  def prefix_label("sci"), do: "Scientific"
  def prefix_label("file"), do: "File"
  def prefix_label("lgeo"), do: "LGeo"
  def prefix_label("sat"), do: "Satellite"
  def prefix_label("view"), do: "View"
  def prefix_label("processing"), do: "Processing"
  def prefix_label(other) when is_binary(other), do: String.capitalize(other)
  def prefix_label(other), do: to_string(other)

  @doc "Keys that dedicated components already render, to be skipped in the generic properties list."
  def dedicated_property_keys do
    ~w(datetime start_datetime end_datetime proj:code proj:epsg proj:wkt2 proj:projjson proj:shape proj:transform proj:bbox proj:geometry proj:centroid table:columns table:row_count table:primary_geometry vector:geometry_types)
  end

  @doc """
  Summarises the projection extension fields of a properties map.

  Handles `proj:code` (`"EPSG:3301"`) and the legacy integer `proj:epsg`, 6- or
  9-element affine transforms, and 4- or 6-element bboxes.
  """
  def proj_summary(props) when is_map(props) do
    code = to_proj_code(Map.get(props, "proj:code")) || to_proj_code(Map.get(props, "proj:epsg"))
    transform = Map.get(props, "proj:transform")

    %{
      code: code,
      epsg: epsg_int(code),
      wkt2: string_or_nil(Map.get(props, "proj:wkt2")),
      projjson: map_or_nil(Map.get(props, "proj:projjson")),
      shape: proj_shape(Map.get(props, "proj:shape")),
      transform: if(is_list(transform), do: transform, else: nil),
      pixel: pixel_size(transform),
      origin: origin(transform),
      bbox: bbox4(Map.get(props, "proj:bbox")),
      centroid: map_or_nil(Map.get(props, "proj:centroid")),
      geometry: map_or_nil(Map.get(props, "proj:geometry"))
    }
  end

  def proj_summary(_), do: proj_summary(%{})

  @doc "True when a projection summary has anything worth showing."
  def proj_present?(%{} = s) do
    s |> Map.drop([:epsg, :pixel, :origin]) |> Map.values() |> Enum.any?(&(&1 != nil))
  end

  def proj_present?(_), do: false

  defp to_proj_code(nil), do: nil
  defp to_proj_code(code) when is_binary(code) and code != "", do: code
  defp to_proj_code(epsg) when is_integer(epsg), do: "EPSG:#{epsg}"
  defp to_proj_code(_), do: nil

  @doc "Integer EPSG code from `\"EPSG:3301\"`, or nil."
  def epsg_int(code) when is_binary(code) do
    case Regex.run(~r/\AEPSG:(\d+)\z/i, code) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  def epsg_int(_), do: nil

  defp proj_shape([rows, cols]) when is_integer(rows) and is_integer(cols), do: {rows, cols}
  defp proj_shape(_), do: nil

  defp pixel_size([_, dx, _, _, _, dy | _]) when is_number(dx) and is_number(dy),
    do: {abs(dx), abs(dy)}

  defp pixel_size(_), do: nil

  defp origin([x0, _, _, y0 | _]) when is_number(x0) and is_number(y0), do: {x0, y0}
  defp origin(_), do: nil

  @doc "Normalises a bbox to `[west, south, east, north]`; 3D bboxes drop the z values. Otherwise nil."
  def bbox4([w, s, e, n] = b)
      when is_number(w) and is_number(s) and is_number(e) and is_number(n),
      do: b

  def bbox4([w, s, _z1, e, n, _z2])
      when is_number(w) and is_number(s) and is_number(e) and is_number(n),
      do: [w, s, e, n]

  def bbox4(_), do: nil

  @doc "Temporal extent of a collection as `{:range, start, end}` or `:none`."
  def temporal_extent(%{"temporal" => %{"interval" => [[s, e] | _]}}) do
    case {parse_datetime(s), parse_datetime(e)} do
      {nil, nil} -> :none
      {ps, pe} -> {:range, ps, pe}
    end
  end

  def temporal_extent(_), do: :none

  @doc "First spatial bbox of a collection extent, or nil."
  def spatial_bbox(%{"spatial" => %{"bbox" => [bbox | _]}}), do: bbox4(bbox)
  def spatial_bbox(_), do: nil

  @doc "SPDX license page for a license identifier, nil for free text like `proprietary`."
  def license_url(license) when is_binary(license) do
    lower = String.downcase(license)

    if lower in ["proprietary", "various", "other"] or
         not String.match?(license, ~r/\A[A-Za-z0-9.+-]+\z/) do
      nil
    else
      "https://spdx.org/licenses/#{license}.html"
    end
  end

  def license_url(_), do: nil

  @doc "Short label for a STAC extension schema URL, e.g. `raster v1.1.0`."
  def extension_label(url) when is_binary(url) do
    case Regex.run(~r{stac-extensions\.github\.io/([^/]+)/v([^/]+)/}, url) do
      [_, name, version] -> "#{name} v#{version}"
      _ -> url
    end
  end

  def extension_label(other), do: to_string(other)

  @doc "`table:columns` of a properties map as a list of maps."
  def table_columns(props) when is_map(props) do
    case Map.get(props, "table:columns") do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  def table_columns(_), do: []

  @doc "True if a properties map carries table/vector extension fields."
  def table_present?(props) when is_map(props) do
    table_columns(props) != [] or
      Enum.any?(
        ["table:row_count", "table:primary_geometry", "vector:geometry_types"],
        &Map.has_key?(props, &1)
      )
  end

  def table_present?(_), do: false

  @doc "True for scalars (nil, binaries, numbers, booleans, atoms)."
  def scalar?(v), do: is_nil(v) or is_binary(v) or is_number(v) or is_boolean(v) or is_atom(v)

  @doc "Pretty JSON for any term; falls back to `inspect/1` when encoding fails."
  def safe_pretty_json(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(data, pretty: true, limit: :infinity)
    end
  end

  defp contains_any?(str, needles), do: Enum.any?(needles, &String.contains?(str, &1))

  defp to_string_safe(nil), do: ""
  defp to_string_safe(v) when is_binary(v), do: v
  defp to_string_safe(v), do: inspect(v)

  defp string_or_nil(v) when is_binary(v) and v != "", do: v
  defp string_or_nil(_), do: nil

  defp map_or_nil(v) when is_map(v) and map_size(v) > 0, do: v
  defp map_or_nil(_), do: nil
end
