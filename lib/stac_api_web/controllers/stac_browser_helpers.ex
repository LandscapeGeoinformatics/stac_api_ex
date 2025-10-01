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
      "Item" -> "bg-green-100 text-green-800"
      "Asset" -> "bg-purple-100 text-purple-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  def type_badge_class("Collection"), do: "bg-blue-100 text-blue-800"
  def type_badge_class("Item"), do: "bg-green-100 text-green-800"
  def type_badge_class("Asset"), do: "bg-purple-100 text-purple-800"
  def type_badge_class(_), do: "bg-gray-100 text-gray-800"

  def get_parent_path(""), do: ""
  def get_parent_path(path) do
    case Path.dirname(path) do
      "." -> ""
      parent -> parent
    end
  end

  # Search result helpers
  def get_item_id(%{id: id}), do: id
  def get_item_id(%{"id" => id}), do: id
  def get_item_id(item) when is_map(item), do: Map.get(item, :id) || Map.get(item, "id")
  def get_item_id(_), do: "Unknown"

  def get_collection_id(%{collection_id: id}), do: id
  def get_collection_id(%{"collection_id" => id}), do: id
  def get_collection_id(item) when is_map(item), do: Map.get(item, :collection_id) || Map.get(item, "collection_id")
  def get_collection_id(_), do: nil

  def get_datetime(%{datetime: dt}), do: dt
  def get_datetime(%{"datetime" => dt}), do: dt
  def get_datetime(item) when is_map(item), do: Map.get(item, :datetime) || Map.get(item, "datetime")
  def get_datetime(_), do: nil

  def get_bbox(%{bbox: bbox}), do: bbox
  def get_bbox(%{"bbox" => bbox}), do: bbox
  def get_bbox(item) when is_map(item), do: Map.get(item, :bbox) || Map.get(item, "bbox")
  def get_bbox(_), do: nil

  def get_properties(%{properties: props}), do: props
  def get_properties(%{"properties" => props}), do: props
  def get_properties(item) when is_map(item), do: Map.get(item, :properties) || Map.get(item, "properties")
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

  # Add these helper functions to your controller or create a view module

defp get_asset_type_icon(asset) do
  case Map.get(asset, "type") do
    "image/tiff" -> "🖼️"
    "image/png" -> "🖼️"
    "image/jpeg" -> "🖼️"
    "application/json" -> "📄"
    "application/geo+json" -> "🗺️"
    "text/xml" -> "📄"
    "application/xml" -> "📄"
    "application/pdf" -> "📕"
    type when is_binary(type) ->
      cond do
        String.contains?(type, "image") -> "🖼️"
        String.contains?(type, "text") -> "📄"
        String.contains?(type, "json") -> "📄"
        String.contains?(type, "xml") -> "📄"
        true -> "📁"
      end
    _ -> "📁"
  end
end

end
