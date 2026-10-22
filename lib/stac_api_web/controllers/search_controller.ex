defmodule StacApiWeb.SearchController do
  use StacApiWeb, :controller
  alias StacApi.Data.{Item, ItemFields, ItemFilters, Search}
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

    with {:ok, filters} <- ItemFilters.parse(search_params),
         {:ok, fields} <- ItemFields.parse(search_params, request_kind(conn.method)) do
      run_search(conn, search_params, authenticated, filters, fields)
    else
      {:error, parameter, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "Invalid #{parameter} parameter: it #{reason}"})
    end
  end

  # Both API paths pass the same parsed filters to Search, preventing silent
  # fallbacks to an unfiltered result set.
  defp run_search(conn, search_params, authenticated, filters, fields) do
    items =
      Search.search(search_params, authenticated, filters)
      |> Enum.map(&ensure_item_struct/1)

    total_count = Search.count_search_results(search_params, authenticated, filters)

    features =
      Enum.map(items, fn item ->
        serialized = Search.serialize_item_for_api(item)

        serialized
        |> Map.put("links", LinkResolver.resolve_links(serialized["links"] || []))
        |> ItemFields.project(fields)
      end)

    response = %{
      "type" => "FeatureCollection",
      "features" => features,
      "numberMatched" => total_count,
      "numberReturned" => length(features),
      "links" =>
        LinkResolver.create_search_links(
          conn,
          ItemFields.pagination_params(search_params, fields),
          total_count
        ),
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

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0
end
