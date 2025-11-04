defmodule StacApiWeb.CatalogsCrudController do
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.Catalog
  alias StacApi.Data.Collection
  alias StacApi.Data.Item
  alias StacApiWeb.DynamicLinkGenerator
  import Ecto.Query

  @doc """
  POST /api/stac/v1/catalogs
  Create or update a catalog (upsert based on ID)
  """
  def create(conn, params) do
    case validate_catalog_params(params) do
      {:ok, catalog_attrs} ->
        case upsert_catalog(catalog_attrs) do
          {:ok, catalog} ->
            # Generate links dynamically
            custom_links = Map.get(catalog_attrs, "links", [])
            links = DynamicLinkGenerator.generate_catalog_links(catalog, custom_links)
            
            catalog_response = %{
              stac_version: catalog.stac_version || "1.0.0",
              type: "Catalog",
              id: catalog.id,
              title: catalog.title,
              description: catalog.description,
              extent: catalog.extent,
              links: links
            }

            success_response = %{
              success: true,
              message: "Catalog created successfully",
              data: catalog_response
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
  GET /api/stac/v1/catalogs/:id
  Get a specific catalog
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(Catalog, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Catalog not found"})

      catalog ->
        # Generate links dynamically
        custom_links = catalog.links || []
        links = DynamicLinkGenerator.generate_catalog_links(catalog, custom_links)
        
        catalog_response = %{
          stac_version: catalog.stac_version || "1.0.0",
          type: "Catalog",
          id: catalog.id,
          title: catalog.title,
          description: catalog.description,
          extent: catalog.extent,
          links: links
        }

        json(conn, catalog_response)
    end
  end

  @doc """
  PUT /api/stac/v1/catalogs/:id
  Replace the entire catalog (full replacement - all fields required)
  """
  def update(conn, %{"id" => id} = params) do
    case Repo.get(Catalog, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Catalog not found"})

      catalog ->
        case validate_catalog_params_full(params) do
          {:ok, catalog_attrs} ->
            case replace_catalog(catalog, catalog_attrs) do
              {:ok, updated_catalog} ->
                # Generate links dynamically
                custom_links = Map.get(catalog_attrs, "links", [])
                links = DynamicLinkGenerator.generate_catalog_links(updated_catalog, custom_links)
                
                catalog_response = %{
                  stac_version: updated_catalog.stac_version || "1.0.0",
                  type: "Catalog",
                  id: updated_catalog.id,
                  title: updated_catalog.title,
                  description: updated_catalog.description,
                  extent: updated_catalog.extent,
                  links: links
                }

                success_response = %{
                  success: true,
                  message: "Catalog replaced successfully",
                  data: catalog_response
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
  PATCH /api/stac/v1/catalogs/:id
  Partially update a catalog (only provided fields are updated)
  """
  def patch(conn, %{"id" => id} = params) do
    case Repo.get(Catalog, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Catalog not found"})

      catalog ->
        case validate_catalog_params_partial(params) do
          {:ok, catalog_attrs} ->
            case update_catalog_partial(catalog, catalog_attrs) do
              {:ok, updated_catalog} ->
                # Reload to ensure we have all fields (especially important for partial updates)
                reloaded_catalog = Repo.get(Catalog, id)
                
                # Generate links dynamically (use updated links if provided, otherwise existing)
                links = if Map.has_key?(params, "links") do
                  custom_links = Map.get(catalog_attrs, "links", reloaded_catalog.links || [])
                  DynamicLinkGenerator.generate_catalog_links(reloaded_catalog, custom_links)
                else
                  DynamicLinkGenerator.generate_catalog_links(reloaded_catalog, reloaded_catalog.links || [])
                end
                
                catalog_response = %{
                  stac_version: reloaded_catalog.stac_version || "1.0.0",
                  type: "Catalog",
                  id: reloaded_catalog.id,
                  title: reloaded_catalog.title,
                  description: reloaded_catalog.description,
                  extent: reloaded_catalog.extent,
                  links: links
                }

                success_response = %{
                  success: true,
                  message: "Catalog updated successfully",
                  data: catalog_response
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
  DELETE /api/stac/v1/catalogs/:id
  Delete a specific catalog
  """
  def delete(conn, %{"id" => id}) do
    case Repo.get(Catalog, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Catalog not found"})

      catalog ->
        # Cascade delete: First delete child collections and their items, then child catalogs
        deleted_counts = cascade_delete_catalog(id)

        case Repo.delete(catalog) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Catalog deleted successfully",
              cascade_deleted: deleted_counts
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete catalog", details: format_changeset_errors(changeset)})
        end
    end
  end

  @doc """
  GET /api/stac/v1/catalogs
  List all catalogs
  """
  def index(conn, _params) do
    catalogs = Repo.all(Catalog)
    
    catalogs_with_links = Enum.map(catalogs, fn catalog ->
      custom_links = catalog.links || []
      links = DynamicLinkGenerator.generate_catalog_links(catalog, custom_links)
      
      %{
        stac_version: catalog.stac_version || "1.0.0",
        type: "Catalog",
        id: catalog.id,
        title: catalog.title,
        description: catalog.description,
        extent: catalog.extent,
        links: links
      }
    end)

    json(conn, %{
      catalogs: catalogs_with_links,
      links: [
        %{"rel" => "self", "href" => "/api/stac/v1/catalogs", "type" => "application/json"},
        %{"rel" => "root", "href" => "/api/stac/v1/", "type" => "application/json"}
      ]
    })
  end

  # Private helper functions

  defp cascade_delete_catalog(catalog_id) do
    # First, get all child collections for this catalog
    child_collections = from(c in Collection, where: c.catalog_id == ^catalog_id) |> Repo.all()
    
    # Delete items for each child collection
    items_deleted = Enum.reduce(child_collections, 0, fn collection, acc ->
      items_count = from(i in StacApi.Data.Item, where: i.collection_id == ^collection.id) |> Repo.aggregate(:count, :id)
      from(i in StacApi.Data.Item, where: i.collection_id == ^collection.id) |> Repo.delete_all()
      acc + items_count
    end)
    
    # Delete child collections
    {collections_deleted, _} = from(c in Collection, where: c.catalog_id == ^catalog_id) |> Repo.delete_all()
    
    # Get child catalogs and recursively delete them
    child_catalogs = from(c in Catalog, where: c.parent_catalog_id == ^catalog_id) |> Repo.all()
    
    # Recursively cascade delete child catalogs
    catalogs_deleted = Enum.reduce(child_catalogs, 0, fn child_catalog, acc ->
      child_deleted_counts = cascade_delete_catalog(child_catalog.id)
      {_, _} = from(c in Catalog, where: c.id == ^child_catalog.id) |> Repo.delete_all()
      acc + 1 + child_deleted_counts.catalogs
    end)
    
    %{
      items: items_deleted,
      collections: collections_deleted,
      catalogs: catalogs_deleted
    }
  end

  defp validate_catalog_params_full(params) do
    required_fields = ["id"]
    missing_fields = Enum.filter(required_fields, &is_nil(params[&1]))

    if length(missing_fields) > 0 do
      {:error, "PUT requires all fields. Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      catalog_attrs = %{
        "id" => params["id"],
        "title" => params["title"],
        "description" => params["description"],
        "type" => params["type"] || "Catalog",
        "stac_version" => params["stac_version"] || "1.0.0",
        "extent" => params["extent"],
        "links" => params["links"] || [],
        "parent_catalog_id" => params["parent_catalog_id"],
        "depth" => calculate_depth(params["parent_catalog_id"])
      }
      {:ok, catalog_attrs}
    end
  end

  defp validate_catalog_params_partial(params) do
    if is_nil(params["id"]) do
      {:error, "Missing required field: id"}
    else
      depth_value = if params["parent_catalog_id"], do: calculate_depth(params["parent_catalog_id"]), else: nil
      
      catalog_attrs = %{}
      |> Map.put("id", params["id"])
      |> maybe_put("title", params["title"])
      |> maybe_put("description", params["description"])
      |> maybe_put("type", params["type"])
      |> maybe_put("stac_version", params["stac_version"])
      |> maybe_put("extent", params["extent"])
      |> maybe_put("links", params["links"])
      |> maybe_put("parent_catalog_id", params["parent_catalog_id"])
      |> maybe_put("depth", depth_value)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

      {:ok, catalog_attrs}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_catalog_params(params) do
    # Keep this for backward compatibility with create/upsert
    validate_catalog_params_full(params)
  end

  defp calculate_depth(nil), do: 0
  defp calculate_depth(parent_catalog_id) when is_binary(parent_catalog_id) do
    case Repo.get(Catalog, parent_catalog_id) do
      nil -> 0
      parent -> (parent.depth || 0) + 1
    end
  end
  defp calculate_depth(_), do: 0

  defp upsert_catalog(attrs) do
    case Repo.get(Catalog, attrs["id"]) do
      nil ->
        %Catalog{}
        |> Catalog.changeset(attrs)
        |> Repo.insert()

      existing_catalog ->
        existing_catalog
        |> Catalog.changeset(attrs)
        |> Repo.update()
    end
  end

  defp update_catalog(catalog, attrs) do
    catalog
    |> Catalog.changeset(attrs)
    |> Repo.update()
  end

  defp replace_catalog(catalog, attrs) do
    catalog
    |> Catalog.changeset(attrs)
    |> Repo.update()
  end

  defp update_catalog_partial(catalog, attrs) do
    catalog
    |> Catalog.changeset(attrs)
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
