defmodule StacApiWeb.CollectionsCrudController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.{Collection, Catalog}
  alias StacApiWeb.DynamicLinkGenerator
  import Ecto.Query

  @doc """
  POST /api/stac/v1/collections
  Create or update a collection (upsert based on ID)
  """
  def create(conn, params) do
    case validate_collection_params(params) do
      {:ok, collection_attrs} ->
        case upsert_collection(collection_attrs) do
          {:ok, collection} ->
            # Generate links dynamically
            custom_links = Map.get(collection_attrs, "links", [])
            links = DynamicLinkGenerator.generate_collection_links(collection, custom_links)
            
            collection_response = %{
              stac_version: collection.stac_version || "1.0.0",
              type: "Collection",
              id: collection.id,
              title: collection.title,
              description: collection.description,
              license: collection.license,
              extent: collection.extent,
              summaries: collection.summaries,
              properties: collection.properties,
              stac_extensions: collection.stac_extensions || [],
              links: links
            }

            success_response = %{
              success: true,
              message: "Collection created successfully",
              data: collection_response
            }

            conn
            |> put_status(:created)
            |> json(success_response)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/stac/v1/collections/:id
  Get a specific collection
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(Collection, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Collection not found"})

      collection ->
        # Generate links dynamically
        custom_links = collection.links || []
        links = DynamicLinkGenerator.generate_collection_links(collection, custom_links)
        
        collection_response = %{
          stac_version: collection.stac_version || "1.0.0",
          type: "Collection",
          id: collection.id,
          title: collection.title,
          description: collection.description,
          license: collection.license,
          extent: collection.extent,
          summaries: collection.summaries,
          properties: collection.properties,
          stac_extensions: collection.stac_extensions || [],
          links: links
        }

        json(conn, collection_response)
    end
  end

  @doc """
  PUT /api/stac/v1/collections/:id
  Update a specific collection
  """
  def update(conn, %{"id" => id} = params) do
    case Repo.get(Collection, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Collection not found"})

      collection ->
        case validate_collection_params(params) do
          {:ok, collection_attrs} ->
            case update_collection(collection, collection_attrs) do
              {:ok, updated_collection} ->
                # Generate links dynamically
                custom_links = Map.get(collection_attrs, "links", [])
                links = DynamicLinkGenerator.generate_collection_links(updated_collection, custom_links)
                
                collection_response = %{
                  stac_version: updated_collection.stac_version || "1.0.0",
                  type: "Collection",
                  id: updated_collection.id,
                  title: updated_collection.title,
                  description: updated_collection.description,
                  license: updated_collection.license,
                  extent: updated_collection.extent,
                  summaries: updated_collection.summaries,
                  properties: updated_collection.properties,
                  stac_extensions: updated_collection.stac_extensions || [],
                  links: links
                }

                success_response = %{
                  success: true,
                  message: "Collection updated successfully",
                  data: collection_response
                }

                json(conn, success_response)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
            end

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: reason})
        end
    end
  end

  @doc """
  DELETE /api/stac/v1/collections/:id
  Delete a specific collection
  """
  def delete(conn, %{"id" => id}) do
    case Repo.get(Collection, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Collection not found"})

      collection ->
        # Cascade delete: Delete all items in this collection first
        items_deleted = cascade_delete_collection(id)

        case Repo.delete(collection) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Collection deleted successfully",
              cascade_deleted: %{items: items_deleted}
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete collection", details: format_changeset_errors(changeset)})
        end
    end
  end

  @doc """
  GET /api/stac/v1/collections
  List all collections
  """
  def index(conn, _params) do
    collections = Repo.all(Collection)
    
    collections_with_links = Enum.map(collections, fn collection ->
      custom_links = collection.links || []
      links = DynamicLinkGenerator.generate_collection_links(collection, custom_links)
      
      %{
        stac_version: collection.stac_version || "1.0.0",
        type: "Collection",
        id: collection.id,
        title: collection.title,
        description: collection.description,
        license: collection.license,
        extent: collection.extent,
        summaries: collection.summaries,
        properties: collection.properties,
        stac_extensions: collection.stac_extensions || [],
        links: links
      }
    end)

    json(conn, %{
      collections: collections_with_links,
      links: [
        %{"rel" => "self", "href" => "/api/stac/v1/collections", "type" => "application/json"},
        %{"rel" => "root", "href" => "/api/stac/v1/", "type" => "application/json"}
      ]
    })
  end

  # Private helper functions

  defp cascade_delete_collection(collection_id) do
    # Count items before deletion for reporting
    items_count = from(i in StacApi.Data.Item, where: i.collection_id == ^collection_id) |> Repo.aggregate(:count, :id)
    
    # Delete all items in this collection
    {_, _} = from(i in StacApi.Data.Item, where: i.collection_id == ^collection_id) |> Repo.delete_all()
    
    items_count
  end

  defp validate_collection_params(params) do
    required_fields = ["id"]
    missing_fields = Enum.filter(required_fields, &is_nil(params[&1]))

    if length(missing_fields) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      # Validate catalog_id if provided
      catalog_id = params["catalog_id"]
      if catalog_id && !Repo.get(Catalog, catalog_id) do
        {:error, "Referenced catalog does not exist"}
      else
        collection_attrs = %{
          "id" => params["id"],
          "title" => params["title"],
          "description" => params["description"],
          "license" => params["license"],
          "extent" => params["extent"],
          "summaries" => params["summaries"],
          "properties" => params["properties"] || %{},
          "stac_version" => params["stac_version"] || "1.0.0",
          "stac_extensions" => params["stac_extensions"] || [],
          "links" => params["links"] || [],
          "catalog_id" => catalog_id
        }
        {:ok, collection_attrs}
      end
    end
  end

  defp upsert_collection(attrs) do
    case Repo.get(Collection, attrs["id"]) do
      nil ->
        %Collection{}
        |> Collection.changeset(attrs)
        |> Repo.insert()

      existing_collection ->
        existing_collection
        |> Collection.changeset(attrs)
        |> Repo.update()
    end
  end

  defp update_collection(collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
