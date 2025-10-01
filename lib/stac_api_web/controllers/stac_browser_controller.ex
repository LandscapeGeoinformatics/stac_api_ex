defmodule StacApiWeb.StacBrowserController do
  use StacApiWeb, :controller
  require Logger
  alias StacApi.Data.Search

  @stac_data_path "priv/stac_data"

  def index(conn, params) do
    path = get_path_from_params(params)
    conn
    |> put_layout(false)
    |> browse_directory(path)
  end

  def show(conn, %{"path" => path_segments} = _params) when is_list(path_segments) do
    path = Enum.join(path_segments, "/")
    conn
    |> put_layout(false)
    |> browse_directory(path)
  end

  def show(conn, %{"path" => path} = _params) when is_binary(path) do
    conn
    |> put_layout(false)
    |> browse_directory(path)
  end

  def show(conn, _params) do
    conn
    |> put_layout(false)
    |> browse_directory("")
  end

  def search(conn, params) do
    search_params = normalize_search_params(params)

    case search_params do
      %{} when map_size(search_params) == 0 ->
        # No search parameters, show search form
        conn
        |> put_layout(false)
        |> assign(:search_results, [])
        |> assign(:search_params, %{})
        |> assign(:total_count, 0)
        |> render(:search)

      _ ->
        # Perform search
        items = Search.search(search_params)
        total_count = Search.count_search_results(search_params)

        conn
        |> put_layout(false)
        |> assign(:search_results, items)
        |> assign(:search_params, search_params)
        |> assign(:total_count, total_count)
        |> render(:search)
    end
  end

  def search_api(conn, params) do
    search_params = normalize_search_params(params)

    items = Search.search(search_params)
    total_count = Search.count_search_results(search_params)

    features = Enum.map(items, &Search.serialize_item_for_api/1)

    response = %{
      "type" => "FeatureCollection",
      "features" => features,
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

  defp get_path_from_params(params) do
    case params do
      %{"path" => path_segments} when is_list(path_segments) ->
        Enum.join(path_segments, "/")
      %{"path" => path} when is_binary(path) ->
        path
      _ ->
        ""
    end
  end

  defp browse_directory(conn, relative_path) do
    full_path = Path.join(@stac_data_path, relative_path)

    case File.exists?(full_path) and File.dir?(full_path) do
      true ->
        case File.ls(full_path) do
          {:ok, entries} ->
            items = build_directory_items(full_path, entries, relative_path)
            breadcrumbs = build_breadcrumbs(relative_path)

            conn
            |> assign(:items, items)
            |> assign(:current_path, relative_path)
            |> assign(:breadcrumbs, breadcrumbs)
            |> assign(:collection_path, get_collection_path(relative_path))
            |> render(:index)

          {:error, reason} ->
            Logger.error("Failed to read directory #{full_path}: #{reason}")
            conn
            |> put_flash(:error, "Unable to read directory")
            |> redirect(to: ~p"/stac/browse")
        end

      false ->
        if File.exists?(full_path) and not File.dir?(full_path) do
          serve_file(conn, full_path, relative_path)
        else
          conn
          |> put_flash(:error, "Directory not found")
          |> redirect(to: ~p"/stac/browse")
        end
    end
  end

  defp build_directory_items(full_path, entries, current_path) do
    entries
    |> Enum.map(fn entry ->
      entry_path = Path.join(full_path, entry)
      relative_entry_path = if current_path == "", do: entry, else: Path.join(current_path, entry)

      stat = File.stat!(entry_path)

      %{
        name: entry,
        type: get_item_type(entry_path, entry),
        path: relative_entry_path,
        size: format_size(stat.size),
        modified: format_date(stat.mtime),
        is_directory: File.dir?(entry_path)
      }
    end)
    |> Enum.sort_by(&{!&1.is_directory, &1.name})
  end

  defp get_item_type(path, name) do
    cond do
      File.dir?(path) -> "Collection"
      String.ends_with?(name, ".json") -> "Item"
      String.ends_with?(name, ".tif") or String.ends_with?(name, ".tiff") -> "Asset"
      true -> "File"
    end
  end

  defp format_size(size) when size < 1024, do: "#{size} B"
  defp format_size(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_size(size) when size < 1024 * 1024 * 1024, do: "#{Float.round(size / (1024 * 1024), 1)} MB"
  defp format_size(size), do: "#{Float.round(size / (1024 * 1024 * 1024), 1)} GB"

  defp format_date({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad_zero(month)}-#{pad_zero(day)} #{pad_zero(hour)}:#{pad_zero(minute)}:#{pad_zero(second)}"
  end

  defp pad_zero(num) when num < 10, do: "0#{num}"
  defp pad_zero(num), do: "#{num}"

  defp build_breadcrumbs(""), do: [%{name: "Home", path: ""}]
  defp build_breadcrumbs(path) do
    parts = String.split(path, "/", trim: true)

    [%{name: "Home", path: ""}] ++
      (parts
       |> Enum.with_index()
       |> Enum.map(fn {part, index} ->
         breadcrumb_path = parts |> Enum.take(index + 1) |> Enum.join("/")
         %{name: part, path: breadcrumb_path}
       end))
  end

  defp get_collection_path(path) do
    case String.split(path, "/", trim: true) do
      [] -> nil
      [collection] -> collection
      [collection | _] -> collection
    end
  end

  defp serve_file(conn, file_path, relative_path) do
    case File.read(file_path) do
      {:ok, content} ->
        content_type = get_content_type(file_path)

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("content-disposition", "inline; filename=\"#{Path.basename(file_path)}\"")
        |> send_resp(200, content)

      {:error, reason} ->
        Logger.error("Failed to read file #{file_path}: #{reason}")
        conn
        |> put_status(404)
        |> json(%{error: "File not found"})
    end
  end

  defp get_content_type(file_path) do
    case Path.extname(file_path) do
      ".json" -> "application/json"
      ".tif" -> "image/tiff"
      ".tiff" -> "image/tiff"
      ".geojson" -> "application/geo+json"
      _ -> "application/octet-stream"
    end
  end

  defp normalize_search_params(params) do
    params
    |> Enum.into(%{}, fn
      {key, value} when is_atom(key) -> {to_string(key), value}
      {key, value} -> {key, value}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0
end
