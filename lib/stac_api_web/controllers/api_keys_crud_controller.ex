defmodule StacApiWeb.ApiKeysCrudController do
  @moduledoc """
  Management endpoints for personalized API keys, mounted under
  `/stac/manage/v1/api-keys`.

  Every action requires the static read-write key `STAC_API_KEY`
  (`StacApiWeb.Plugs.AuthPlug` with `admin_only: true`). Issued keys, even
  read-write ones, get 401 here, so they can never mint or change keys.

  A key has a `role`, `read_only` (default) or `read_write`, fixed when the key
  is created: PATCH rejects a `role` with 422, and changing a role means
  issuing a new key and deleting the old one. Read-only keys read the public
  STAC API; read-write keys can also write catalogs, collections and items.
  Secrets start with `stac_ro_` or `stac_rw_` to match the role. Optional
  `expires_at` (a future ISO 8601 time; `null` = never), `contact` and `note`
  say how long, for whom and why a key exists.

  Only a SHA-256 hash of each secret is stored. The raw secret is returned
  once, under `data.key`, by `create/2` and `rotate/2`; every other response
  exposes just the non-secret `key_prefix`.

  Names are trimmed, 1-100 characters and unique. Responses use `404` for
  unknown ids (including non-numeric ones) and `422` with a `details` map
  (`%{field => [message]}`) for validation errors, e.g. a blank or duplicate
  name or an `expires_at` in the past. Each key reports `last_used_at` (`null` if never used, otherwise
  accurate to about an hour).
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
  Creates a new key for `params["name"]` with `role` (default `read_only`) and
  optional `expires_at`, `contact` and `note`. The raw secret is returned
  once, under `data.key`, and cannot be retrieved again — only rotated.
  """
  def create(conn, params) do
    role = params["role"] || "read_only"
    {raw_secret, secret_attrs} = ApiKey.generate_secret(role)

    attrs =
      Map.merge(secret_attrs, %{
        name: params["name"],
        role: role,
        expires_at: params["expires_at"],
        contact: params["contact"],
        note: params["note"]
      })

    case %ApiKey{} |> ApiKey.changeset(attrs) |> Repo.insert() do
      {:ok, api_key} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "API key created successfully. Store the key now; it cannot be shown again.",
          data: to_json(api_key, raw_secret)
        })

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  @doc """
  PATCH /stac/manage/v1/api-keys/:id
  Edits `name`, `expires_at`, `contact` and `note`; fields that are not sent
  stay unchanged. The secret is untouched (use `rotate` for that) and the role
  cannot be changed: a request with `role` gets 422.
  """
  def update(conn, %{"id" => id} = params) do
    case fetch(id) do
      nil ->
        not_found(conn)

      _api_key when is_map_key(params, "role") ->
        role_change_error(conn)

      api_key ->
        attrs = Map.take(params, ["name", "expires_at", "contact", "note"])

        case api_key |> ApiKey.update_changeset(attrs) |> Repo.update() do
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
  Issues a new secret for an existing key: same id, same name and role (so the
  prefix still matches), old secret immediately stops working. The new raw
  secret is returned once, under `data.key`. It also sets `rotated_at` and
  `rotated_by: "admin"`.

  `expires_at` is the admin's final date and no rotation moves it: an expired
  key can be rotated, but the new secret is expired as well. The response
  returns `expires_at`; to revive the key, PATCH it to a future date.
  """
  def rotate(conn, %{"id" => id}) do
    case fetch(id) do
      nil ->
        not_found(conn)

      api_key ->
        case ApiKey.rotate_secret(api_key, "admin") do
          {:ok, updated, raw_secret} ->
            json(conn, %{
              success: true,
              message:
                "API key rotated successfully. Store the new key now; " <>
                  "it cannot be shown again, and the old one no longer works.",
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

  defp role_change_error(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "Validation failed",
      details: %{
        role: ["cannot be changed; issue a new key with the role you need and delete this one"]
      }
    })
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
      role: api_key.role,
      expires_at: api_key.expires_at,
      contact: api_key.contact,
      note: api_key.note,
      last_used_at: api_key.last_used_at,
      rotated_at: api_key.rotated_at,
      rotated_by: api_key.rotated_by,
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
