defmodule StacApiWeb.SearchController do
  use StacApiWeb, :controller
  alias StacApi.Data.{Item, ItemFields, ItemFilters, ItemListing, Search}
  alias StacApiWeb.LinkResolver

  def index(conn, params) do
    # Handle both GET (query params) and POST (body params)
    search_params =
      case conn.method do
        "POST" ->
          case conn.body_params do
            %{} = body_params -> normalize_params(body_params)
            _ -> normalize_params(params)
          end

        _ ->
          normalize_params(params)
      end

    authenticated = conn.assigns[:authenticated] || false
    kind = request_kind(conn.method)

    with {:ok, filters} <- ItemFilters.parse(search_params),
         {:ok, fields} <- ItemFields.parse(search_params, kind),
         {:ok, listing} <- ItemListing.parse(search_params) do
      run_search(conn, kind, search_params, authenticated, filters, fields, listing)
    else
      {:error, parameter, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "Invalid #{parameter} parameter: it #{reason}"})
    end
  end

  # Both API paths pass the same parsed filters to Search, preventing silent
  # fallbacks to an unfiltered result set.
  defp run_search(conn, kind, search_params, authenticated, filters, fields, listing) do
    items =
      Search.search(search_params, authenticated, filters, listing)
      |> Enum.map(&ensure_item_struct/1)

    total_count = Search.count_search_results(search_params, authenticated, filters)

    features =
      Enum.map(items, fn item ->
        item
        |> Search.serialize_item_for_api()
        |> ItemFields.project(fields)
      end)

    # POST links repeat the request body as it was sent; only GET links need
    # the comma-separated form of fields and sortby.
    link_params =
      case kind do
        :post ->
          search_params

        :get ->
          search_params
          |> ItemFields.pagination_params(fields)
          |> ItemListing.pagination_params(listing)
      end

    response = %{
      "type" => "FeatureCollection",
      "features" => features,
      "numberMatched" => total_count,
      "numberReturned" => length(features),
      "links" => LinkResolver.create_search_links(kind, link_params, listing, total_count),
      "context" => %{
        "returned" => length(features),
        "matched" => total_count,
        "limit" => listing.limit
      }
    }

    conn
    |> put_resp_content_type("application/geo+json")
    |> json(response)
  end

  defp ensure_item_struct(%Item{} = item), do: item

  defp ensure_item_struct(item) when is_map(item) do
    %Item{
      id: item["id"] || item[:id],
      stac_version: item["stac_version"] || item[:stac_version],
      stac_extensions: item["stac_extensions"] || item[:stac_extensions] || [],
      geometry: item["geometry"] || item[:geometry],
      bbox: item["bbox"] || item[:bbox],
      datetime: item["datetime"] || item[:datetime],
      properties: item["properties"] || item[:properties] || %{},
      assets: item["assets"] || item[:assets] || %{},
      links: item["links"] || item[:links] || [],
      collection_id: item["collection_id"] || item[:collection_id],
      inserted_at: item["inserted_at"] || item[:inserted_at],
      updated_at: item["updated_at"] || item[:updated_at]
    }
  end

  defp normalize_params(params) do
    params
    |> Enum.into(%{}, fn
      {key, value} when is_atom(key) -> {to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp request_kind("POST"), do: :post
  defp request_kind(_method), do: :get
end
