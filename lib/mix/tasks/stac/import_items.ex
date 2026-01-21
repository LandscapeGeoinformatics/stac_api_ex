defmodule Mix.Tasks.Stac.ImportItems do
  @moduledoc """
  Import STAC items from a directory into a collection via REST API.

  ## Examples

      mix stac.import_items items/
      mix stac.import_items items/ --collection my_collection
      mix stac.import_items items/ --dry-run
      mix stac.import_items items/ --base-url http://localhost:4000
  """

  use Mix.Task
  require Finch

  @shortdoc "Import STAC items into a collection via REST API"

  @switches [
    collection: :string,
    dry_run: :boolean,
    catalog_id: :string,
    base_url: :string,
    api_key: :string
  ]

  @default_base_url "http://localhost:4000"
  @default_extent %{
    "spatial" => %{"bbox" => [[-180, -90, 180, 90]]},
    "temporal" => %{"interval" => [["", ""]]}
  }

  def run(args) do
    {opts, args, _} = OptionParser.parse(args, switches: @switches)

    case args do
      [items_dir] ->
        Application.ensure_all_started(:stac_api)
        import_items_dir(items_dir, opts)
      _ -> Mix.shell().error("Usage: mix stac.import_items <items_dir> [--collection COLLECTION_ID] [--dry-run] [--base-url URL] [--api-key KEY]"); exit({:shutdown, 1})
    end
  end

  defp import_items_dir(items_dir, opts) do
    unless File.dir?(items_dir), do: Mix.raise("Directory #{items_dir} not found")

    base_url = Keyword.get(opts, :base_url, @default_base_url)
    json_files = Path.wildcard("#{items_dir}/*.json")

    if json_files == [], do: Mix.raise("No JSON files found in #{items_dir}")

    items = Enum.map(json_files, fn file ->
      File.read!(file) |> Jason.decode!()
    end)

    collection_id = Keyword.get(opts, :collection) || get_collection_id(items)
    api_key = Keyword.get(opts, :api_key) || System.get_env("STAC_API_KEY") || "dev-api-key-2024"
    Mix.shell().info("Collection ID: #{collection_id}")

    unless check_collection_exists(base_url, collection_id, api_key) do
      if opts[:dry_run] do
        Mix.shell().info("[DRY RUN] Would create collection: #{collection_id}")
      else
        create_collection(base_url, collection_id, opts[:catalog_id], api_key)
      end
    end

    if opts[:dry_run] do
      Mix.shell().info("[DRY RUN] Would import #{length(items)} items:")
      Enum.each(items, &Mix.shell().info("  - #{&1["id"]}"))
    else
      count = import_items_via_api(base_url, items, collection_id, api_key)
      Mix.shell().info("✓ Import complete! #{count}/#{length(items)} items imported")
    end
  end

  # Helpers

  defp get_collection_id([first | _]) do
    first["collection"] || first["collection_id"] || "default-collection"
  end

  defp check_collection_exists(base_url, collection_id, _api_key) do
    url = "#{base_url}/stac/api/v1/collections/#{collection_id}"

    case Finch.build(:get, url) |> Finch.request(StacApi.Finch) do
      {:ok, %Finch.Response{status: 200}} -> true
      {:ok, %Finch.Response{status: 404}} -> false
      {:error, _} -> false
    end
  end

  defp create_collection(base_url, collection_id, catalog_id, api_key) do
    payload = %{
      id: collection_id,
      title: collection_id,
      description: "Collection imported from #{collection_id}",
      license: "CC-BY-4.0",
      extent: @default_extent,
      stac_version: "1.0.0",
      stac_extensions: [],
      links: [],
      properties: %{},
      summaries: %{}
    }
    |> maybe_add_catalog_id(catalog_id)

    url = "#{base_url}/stac/api/v1/collections"
    body = Jason.encode!(payload)
    headers = [{"content-type", "application/json"}, {"x-api-key", api_key}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, StacApi.Finch) do
      {:ok, %Finch.Response{status: 201}} -> Mix.shell().info("✓ Collection created")
      {:ok, %Finch.Response{status: s, body: b}} -> Mix.raise("Error creating collection (#{s}): #{b}")
      {:error, reason} -> Mix.raise("Error creating collection: #{inspect(reason)}")
    end
  end

  defp maybe_add_catalog_id(payload, nil), do: payload
  defp maybe_add_catalog_id(payload, catalog_id), do: Map.put(payload, :catalog_id, catalog_id)

  defp import_items_via_api(base_url, items, collection_id, api_key) do
    payload = %{
      features: Enum.map(items, fn item -> Map.put(item, "collection_id", collection_id) |> Map.delete("collection") end)
    }

    url = "#{base_url}/stac/api/v1/items/import"
    body = Jason.encode!(payload)
    headers = [{"content-type", "application/json"}, {"x-api-key", api_key}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, StacApi.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        %{"imported" => imported, "failed" => failed} = Jason.decode!(response_body)
        if failed > 0, do: Mix.shell().warn("#{failed} items failed")
        imported
      _ -> 0
    end
  end
end
