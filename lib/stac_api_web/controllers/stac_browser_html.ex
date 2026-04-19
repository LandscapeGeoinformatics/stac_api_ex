defmodule StacApiWeb.StacBrowserHTML do
  use StacApiWeb, :html

  import StacApiWeb.StacBrowserHelpers

  embed_templates "stac_browser_html/*"

  # Map component for displaying collection extent and item geometry
  def stac_map(assigns) do
    geojson_data =
      if assigns[:geometry] && assigns[:properties] do
        geometry = convert_geography_to_geojson(assigns[:geometry])
        geometry && %{"type" => "Feature", "geometry" => geometry, "properties" => assigns[:properties]}
      else
        extent = assigns[:geojson_data] || %{}
        convert_extent_to_geojson(extent)
      end

    encoded =
      case Jason.encode(geojson_data) do
        {:ok, json} -> json
        {:error, _} -> "null"
      end

    assigns = assign(assigns, :encoded_geojson, encoded)

    ~H"""
    <div
      id={@map_id}
      class="w-full h-96 rounded-lg border border-gray-300 shadow-sm"
      data-map-id={@map_id}
      data-geojson={@encoded_geojson}
    >
    </div>
    """
  end

  # Convert PostGIS Geo.* objects to GeoJSON format
  defp convert_geography_to_geojson(%Geo.Polygon{coordinates: coords}) do
    # Convert tuples to lists recursively
    coordinates = convert_tuples_to_lists(coords)
    %{"type" => "Polygon", "coordinates" => coordinates}
  end

  defp convert_geography_to_geojson(%Geo.Point{coordinates: {lon, lat}}) do
    %{"type" => "Point", "coordinates" => [lon, lat]}
  end

  defp convert_geography_to_geojson(_), do: nil

  # Recursively convert tuples to lists for JSON encoding
  defp convert_tuples_to_lists(data) when is_tuple(data) do
    data |> Tuple.to_list() |> convert_tuples_to_lists()
  end

  defp convert_tuples_to_lists(data) when is_list(data) do
    Enum.map(data, &convert_tuples_to_lists/1)
  end

  defp convert_tuples_to_lists(data), do: data

  # Convert extent JSON to GeoJSON feature
  defp convert_extent_to_geojson(%{"spatial" => %{"bbox" => [bbox_list | _]}} = _extent) do
    [min_lon, min_lat, max_lon, max_lat] = bbox_list
    %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "Polygon",
        "coordinates" => [[
          [min_lon, min_lat],
          [max_lon, min_lat],
          [max_lon, max_lat],
          [min_lon, max_lat],
          [min_lon, min_lat]
        ]]
      }
    }
  end

  defp convert_extent_to_geojson(extent) when is_map(extent), do: extent
  defp convert_extent_to_geojson(_), do: %{}
end
