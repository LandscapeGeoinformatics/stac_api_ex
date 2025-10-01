# lib/stac_api/data/importer.ex
defmodule StacApi.Data.Importer do
  @moduledoc """
  Imports STAC JSON data into the database
  """

  alias StacApi.Repo
  alias StacApi.Data.{Collection, Item}
  require Logger

  def import_from_directory(data_path \\ "priv/stac_data") do
    Logger.info("Starting STAC data import from #{data_path}")

    collections_imported = import_collections(data_path)
    Logger.info("Imported #{collections_imported} collections")

    items_imported = import_items(data_path)
    Logger.info("Imported #{items_imported} items")

    {:ok, %{collections: collections_imported, items: items_imported}}
  end

  defp import_collections(data_path) do
    collection_files = Path.join([data_path, "**", "collection.json"])

    collection_files
    |> Path.wildcard()
    |> Enum.map(&import_collection_file/1)
    |> Enum.count(& &1 == :ok)
  end

  defp import_collection_file(file_path) do
    try do
      collection_data = file_path |> File.read!() |> Jason.decode!()

      collection_attrs = %{
        id: collection_data["id"],
        title: collection_data["title"],
        description: collection_data["description"],
        license: collection_data["license"],
        extent: collection_data["extent"],
        summaries: collection_data["summaries"],
        properties: collection_data["properties"] || %{},
        stac_version: collection_data["stac_version"],
        stac_extensions: collection_data["stac_extensions"] || [],
        links: make_links_relative(collection_data["links"] || [])
      }

      %Collection{}
      |> Collection.changeset(collection_attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :id)

      :ok
    rescue
      error ->
        Logger.error("Failed to import collection from #{file_path}: #{inspect(error)}")
        :error
    end
  end

  defp import_items(data_path) do
    # Find all JSON files that are not collection.json or catalog.json
    item_pattern = Path.join([data_path, "**", "*.json"])

    item_pattern
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "collection.json"))
    |> Enum.reject(&String.ends_with?(&1, "catalog.json"))
    |> Enum.map(&import_item_file/1)
    |> Enum.count(& &1 == :ok)
  end

  defp import_item_file(file_path) do
    try do
      item_data = file_path |> File.read!() |> Jason.decode!()

      # Only process if it's a STAC Item (Feature)
      if item_data["type"] == "Feature" && item_data["geometry"] do
        import_stac_item(item_data)
      else
        :skip
      end
    rescue
      error ->
        Logger.error("Failed to import item from #{file_path}: #{inspect(error)}")
        :error
    end
  end

  defp import_stac_item(item_data) do
    # Parse datetime
    datetime = parse_datetime(get_in(item_data, ["properties", "datetime"]))

    # Convert GeoJSON geometry to PostGIS format
    geometry = case item_data["geometry"] do
      %{"type" => _, "coordinates" => _} = geom ->
        {:ok, geo} = Geo.JSON.decode(geom)
        geo
      _ -> nil
    end

    item_attrs = %{
      id: item_data["id"],
      collection_id: item_data["collection"],
      stac_version: item_data["stac_version"],
      stac_extensions: item_data["stac_extensions"] || [],
      geometry: geometry,
      bbox: item_data["bbox"],
      datetime: datetime,
      properties: item_data["properties"] || %{},
      assets: item_data["assets"] || %{},
      links: make_links_relative(item_data["links"] || [])
    }

    %Item{}
    |> Item.changeset(item_attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :id)

    :ok
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
  defp parse_datetime(_), do: nil

  defp make_links_relative(links) when is_list(links) do
    Enum.map(links, fn link ->
      case link do
        %{"href" => href} = link_map ->
          Map.put(link_map, "href", make_href_relative(href))
        %{href: href} = link_map ->
          Map.put(link_map, :href, make_href_relative(href))
        link ->
          link
      end
    end)
  end

  defp make_href_relative(href) when is_binary(href) do
    # If it's already relative, return as is
    if String.starts_with?(href, "/") do
      href
    else
      # If it's absolute, extract the path part
      case URI.parse(href) do
        %URI{path: path, query: query} ->
          case query do
            nil -> path
            query -> "#{path}?#{query}"
          end
        _ ->
          href
      end
    end
  end
  defp make_href_relative(href), do: href
end

# Mix task to run the import
defmodule Mix.Tasks.Stac.Import do
  use Mix.Task
  alias StacApi.Data.Importer

  @shortdoc "Import STAC data from JSON files"

  def run(args) do
    Mix.Task.run("app.start")

    data_path = case args do
      [path] -> path
      [] -> "priv/stac_data"
      _ ->
        IO.puts("Usage: mix stac.import [data_path]")
        System.halt(1)
    end

    case Importer.import_from_directory(data_path) do
      {:ok, %{collections: c_count, items: i_count}} ->
        IO.puts("✅ Import completed successfully!")
        IO.puts("📁 Collections imported: #{c_count}")
        IO.puts("📄 Items imported: #{i_count}")
      {:error, reason} ->
        IO.puts("❌ Import failed: #{reason}")
        System.halt(1)
    end
  end
end
