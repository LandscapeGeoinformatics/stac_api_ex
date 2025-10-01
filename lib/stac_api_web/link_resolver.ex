defmodule StacApiWeb.LinkResolver do
  @moduledoc """
  Handles resolution of relative URLs to absolute URLs for STAC API responses.
  
  This module provides a centralized way to manage URLs across the application,
  allowing for flexible deployment across different environments while keeping
  relative URLs in the database.
  """

  @doc """
  Resolves a relative URL to an absolute URL using the configured base URL.
  
  ## Examples
  
      iex> resolve_url("/api/stac/v1/collections/test")
      "http://localhost:4000/api/stac/v1/collections/test"
      
      iex> resolve_url("http://example.com/absolute")
      "http://example.com/absolute"
  """
  def resolve_url(url) when is_binary(url) do
    case String.starts_with?(url, ["http://", "https://"]) do
      true -> url  # Already absolute
      false -> "#{base_url()}#{url}"
    end
  end

  @doc """
  Resolves a list of links, converting relative hrefs to absolute URLs.
  
  ## Examples
  
      iex> resolve_links([%{"rel" => "self", "href" => "/api/stac/v1/"}])
      [%{"rel" => "self", "href" => "http://localhost:4000/api/stac/v1/"}]
  """
  def resolve_links(links) when is_list(links) do
    Enum.map(links, fn link ->
      case link do
        %{"href" => href} = link_map ->
          Map.put(link_map, "href", resolve_url(href))
        %{href: href} = link_map ->
          Map.put(link_map, :href, resolve_url(href))
        link ->
          link
      end
    end)
  end

  @doc """
  Resolves links from a Phoenix connection, using the connection's host/scheme
  if available, otherwise falling back to configured base URL.
  """
  def resolve_links_from_conn(conn, links) when is_list(links) do
    base_url = get_base_url_from_conn(conn)
    Enum.map(links, fn link ->
      case link do
        %{"href" => href} = link_map ->
          resolved_href = case String.starts_with?(href, ["http://", "https://"]) do
            true -> href
            false -> "#{base_url}#{href}"
          end
          Map.put(link_map, "href", resolved_href)
        %{href: href} = link_map ->
          resolved_href = case String.starts_with?(href, ["http://", "https://"]) do
            true -> href
            false -> "#{base_url}#{href}"
          end
          Map.put(link_map, :href, resolved_href)
        link ->
          link
      end
    end)
  end

  @doc """
  Creates a standard STAC link with resolved URL.
  """
  def create_link(rel, href, opts \\ []) do
    %{
      "rel" => rel,
      "href" => resolve_url(href),
      "type" => Keyword.get(opts, :type, "application/json"),
      "title" => Keyword.get(opts, :title),
      "method" => Keyword.get(opts, :method)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a list of standard STAC links for collections.
  """
  def create_collection_links(collection_id) do
    [
      create_link("self", "/api/stac/v1/collections/#{collection_id}"),
      create_link("root", "/api/stac/v1/"),
      create_link("items", "/api/stac/v1/collections/#{collection_id}/items", 
                  type: "application/geo+json")
    ]
  end

  @doc """
  Creates a list of standard STAC links for items.
  """
  def create_item_links(collection_id) do
    [
      create_link("collection", "/api/stac/v1/collections/#{collection_id}"),
      create_link("root", "/api/stac/v1/"),
      create_link("self", "/api/stac/v1/collections/#{collection_id}/items",
                  type: "application/geo+json")
    ]
  end

  @doc """
  Creates a list of standard STAC links for search results.
  """
  def create_search_links(conn, params, total_count) do
    base_url = get_base_url_from_conn(conn)
    current_limit = parse_int(params["limit"] || "10")
    current_offset = parse_int(params["offset"] || "0")

    links = [
      create_link("self", "/api/stac/v1/search?#{build_query_string(params)}",
                  type: "application/geo+json"),
      create_link("root", "/api/stac/v1/")
    ]

    links =
      if current_offset > 0 do
        prev_params = Map.put(params, "offset", to_string(max(0, current_offset - current_limit)))
        prev_link = create_link("prev", "/api/stac/v1/search?#{build_query_string(prev_params)}",
                               type: "application/geo+json")
        [prev_link | links]
      else
        links
      end

    if current_offset + current_limit < total_count do
      next_params = Map.put(params, "offset", to_string(current_offset + current_limit))
      next_link = create_link("next", "/api/stac/v1/search?#{build_query_string(next_params)}",
                             type: "application/geo+json")
      [next_link | links]
    else
      links
    end
  end

  # Private functions

  defp base_url do
    Application.get_env(:stac_api, :base_url, "http://localhost:4000")
  end

  defp get_base_url_from_conn(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    port = if (conn.scheme == :https and conn.port == 443) or
              (conn.scheme == :http and conn.port == 80) do
      ""
    else
      ":#{conn.port}"
    end
    "#{scheme}://#{conn.host}#{port}"
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> 0
    end
  end
  defp parse_int(int) when is_integer(int), do: int
  defp parse_int(_), do: 0

  defp build_query_string(params) do
    params
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Enum.map(fn {k, v} ->
      value = case v do
        list when is_list(list) -> Enum.join(list, ",")
        other -> to_string(other)
      end
      "#{k}=#{URI.encode(value)}"
    end)
    |> Enum.join("&")
  end
end
