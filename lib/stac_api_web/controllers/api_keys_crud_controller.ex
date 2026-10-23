defmodule StacApiWeb.ApiKeysCrudController do
  @moduledoc """
  Management endpoints for personalized, read-only API keys, mounted under
  `/stac/manage/v1/api-keys`.

  Like the rest of the management API, every action requires the master
  read-write key (`StacApiWeb.Plugs.AuthPlug`). Keys issued here only ever
  grant read access to the public STAC API (`StacApiWeb.Plugs.ReadAuthPlug`)
  and are independent of the static `STAC_API_KEY` / `STAC_API_KEY_RO`.

  Only a SHA-256 hash of each secret is stored. The raw secret is returned
  once, under `data.key`, by `create/2` and `rotate/2`; every other response
  exposes just the non-secret `key_prefix`.

  Responses use `404` for unknown ids (including non-numeric ones) and `422`
  with a `details` map for validation errors.
  """
  use StacApiWeb, :controller
  alias StacApi.Repo
  alias StacApi.Data.ApiKey
  import Ecto.Query

  @doc """
  GET /stac/manage/v1/api-keys
  Lists issued keys. Secrets are never returned here, only `key_prefix`.
  """
  def index(conn, _params) do
    api_keys = Repo.all(from k in ApiKey, order_by: [desc: k.inserted_at])
    json(conn, %{data: Enum.map(api_keys, &to_json/1)})
  end

  @doc """
  GET /stac/manage/v1/api-keys/:id
  """
  def show(conn, %{"id" => id}) do
    case fetch(id) do
      nil -> not_found(conn)
      api_key -> json(conn, %{data: to_json(api_key)})
    end
  end

  @doc """
  POST /stac/manage/v1/api-keys
  Creates a new read-only key for `params["name"]`. The raw secret is
  returned once, under `data.key`, and cannot be retrieved again — only
  rotated.
  """
  def create(conn, params) do
    {raw_secret, secret_attrs} = ApiKey.generate_secret()
    attrs = Map.put(secret_attrs, :name, params["name"])

    case %ApiKey{} |> ApiKey.changeset(attrs) |> Repo.insert() do
      {:ok, api_key} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "API key created successfully",
          data: to_json(api_key, raw_secret)
        })

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  @doc """
  PATCH /stac/manage/v1/api-keys/:id
  Renames a key. `name` is the only editable field; the secret is
  untouched (use `rotate` for that).
  """
  def update(conn, %{"id" => id} = params) do
    case fetch(id) do
      nil ->
        not_found(conn)

      api_key ->
        case api_key |> ApiKey.changeset(%{name: params["name"]}) |> Repo.update() do
          {:ok, updated} ->
            json(conn, %{
              success: true,
              message: "API key updated successfully",
              data: to_json(updated)
            })

          {:error, changeset} ->
            validation_error(conn, changeset)
        end
    end
  end

  @doc """
  POST /stac/manage/v1/api-keys/:id/rotate
  Issues a new secret for an existing key: same id, same name, old secret
  immediately stops working. The new raw secret is returned once, under
  `data.key`.
  """
  def rotate(conn, %{"id" => id}) do
    case fetch(id) do
      nil ->
        not_found(conn)

      api_key ->
        {raw_secret, secret_attrs} = ApiKey.generate_secret()

        case api_key |> ApiKey.changeset(secret_attrs) |> Repo.update() do
          {:ok, updated} ->
            json(conn, %{
              success: true,
              message: "API key rotated successfully",
              data: to_json(updated, raw_secret)
            })

          {:error, changeset} ->
            validation_error(conn, changeset)
        end
    end
  end

  @doc """
  DELETE /stac/manage/v1/api-keys/:id
  Permanently deletes the key; it stops authenticating immediately.
  """
  def delete(conn, %{"id" => id}) do
    case fetch(id) do
      nil ->
        not_found(conn)

      api_key ->
        {:ok, _} = Repo.delete(api_key)
        json(conn, %{success: true, message: "API key deleted successfully"})
    end
  end

  # Private helpers

  # Looks up a key by its URL id. Non-numeric ids return nil (-> 404) instead
  # of raising.
  defp fetch(id) do
    case Integer.parse(id) do
      {int_id, ""} -> Repo.get(ApiKey, int_id)
      _ -> nil
    end
  end

  defp not_found(conn) do
    conn |> put_status(:not_found) |> json(%{error: "API key not found"})
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
  end

  # Serializes a key. The secret (`key`) is included only when `raw_secret`
  # is given, i.e. on create and rotate.
  defp to_json(api_key, raw_secret \\ nil) do
    base = %{
      id: api_key.id,
      name: api_key.name,
      key_prefix: api_key.key_prefix,
      inserted_at: api_key.inserted_at,
      updated_at: api_key.updated_at
    }

    if raw_secret, do: Map.put(base, :key, raw_secret), else: base
  end

  # Turns changeset errors into a `%{field => [message]}` map.
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
