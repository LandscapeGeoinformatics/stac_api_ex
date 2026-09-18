defmodule StacApiWeb.StacBrowserHTML do
  use StacApiWeb, :html

  import StacApiWeb.StacBrowserHelpers
  import StacApiWeb.StacBrowserComponents

  embed_templates "stac_browser_html/*"

  # Map component for displaying collection extent and item geometry
  def stac_map(assigns) do
    geojson_data =
      if assigns[:geometry] && assigns[:properties] do
        geometry = convert_geography_to_geojson(assigns[:geometry])

        geometry &&
          %{"type" => "Feature", "geometry" => geometry, "properties" => assigns[:properties]}
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

  # Convert any Geo.* struct (Polygon, MultiPolygon, Point, ...) to a GeoJSON map.
  # Returns nil for anything Geo.JSON cannot encode so the map is simply skipped.
  defp convert_geography_to_geojson(%{__struct__: mod} = geo) when is_atom(mod) do
    case Geo.JSON.encode(geo) do
      {:ok, geojson} -> geojson
      _ -> nil
    end
  end

  defp convert_geography_to_geojson(%{"type" => _} = geojson), do: geojson
  defp convert_geography_to_geojson(_), do: nil

  # Convert extent JSON to GeoJSON feature
  defp convert_extent_to_geojson(%{
         "spatial" => %{"bbox" => [[min_lon, min_lat, max_lon, max_lat] | _]}
       })
       when is_number(min_lon) and is_number(min_lat) and is_number(max_lon) and
              is_number(max_lat) do
    %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "Polygon",
        "coordinates" => [
          [
            [min_lon, min_lat],
            [max_lon, min_lat],
            [max_lon, max_lat],
            [min_lon, max_lat],
            [min_lon, min_lat]
          ]
        ]
      }
    }
  end

  defp convert_extent_to_geojson(extent) when is_map(extent), do: extent
  defp convert_extent_to_geojson(_), do: %{}

  attr :browse_authenticated, :boolean, required: true
  attr :current_path, :string, required: true

  def auth_controls(assigns) do
    ~H"""
    <div class="inline-flex items-center space-x-2">
      <%= if @browse_authenticated do %>
        <div class="flex items-center space-x-2">
          <span class="px-2 py-0.5 text-xs font-medium rounded text-primary bg-secondary border border-black">Private: ON</span>
          <form action="/stac/web/logout" method="post" class="inline">
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <input
      type="hidden"
      name="return_to"
      value={@current_path}
    />

    <button
      type="submit"
      class="btn btn-sm bg-secondary text-primary border-black shadow-sm shadow-black/20"
      title="Logout private browsing"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a2 2 0 01-2 2H6a2 2 0 01-2-2V7a2 2 0 012-2h5a2 2 0 012 2v1" />
      </svg>
      Logout
    </button>
    </form>
        </div>
      <% else %>
        <div class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-sm bg-secondary text-primary border-black flex items-center justify-center" title="Unlock private browsing">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </label>
          <form tabindex="0" action="/stac/web/auth" method="post" class="dropdown-content menu p-3 shadow bg-white rounded-box w-56 border border-secondary">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="return_to" value={@current_path} />
            <div class="form-control">
              <label class="label p-0 mb-1"><span class="label-text text-xs text-secondary">API Key</span></label>
              <input
                name="api_key"
                type="password"
                placeholder="Enter API key"
                class="input input-sm w-full border-secondary focus:border-primary"
                autocomplete="current-password"
              />
            </div>
            <div class="mt-3 text-right">
              <button
                type="submit"
                class="btn btn-sm bg-secondary text-primary border-black shadow-sm shadow-black/20"
              >
                Unlock
              </button>
            </div>
          </form>
        </div>
      <% end %>
    </div>
    """
  end
end
