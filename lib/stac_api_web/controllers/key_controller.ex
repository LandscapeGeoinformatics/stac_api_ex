defmodule StacApiWeb.KeyController do
  @moduledoc """
  Self-service for the owner of a personalized API key, mounted under
  `/stac/api/v1/key`.

  Both endpoints are authenticated by the key itself (`X-API-Key`) and only
  ever touch that key. The static env keys (`STAC_API_KEY`,
  `STAC_API_KEY_RO`) are not issued keys, so they get 404; no key, an invalid
  key, an expired key or a key past the max-age gets 401.

    * `GET /key` returns the key's own `name`, `role`, `key_prefix`,
      `expires_at`, `rotated_at`, `secret_expires_at` and `last_used_at`. The
      hash, the secret and the admin metadata (`contact`, `note`) are never
      returned.
    * `POST /key/rotate` issues a new secret, shown once under `data.key`; the
      old one stops working immediately. Only the secret, `key_prefix` and
      `rotated_at` / `rotated_by: "self"` change. `expires_at` is the admin's
      final date and is never moved. At most one self-rotation per key per
      hour (429 with `Retry-After`).
  """
  use StacApiWeb, :controller

  alias StacApi.Data.ApiKey

  # Requires an issued key on the conn (assigned by ReadAuthPlug).
  plug :require_issued_key

  @doc """
  GET /stac/api/v1/key
  """
  def show(conn, _params) do
    json(conn, %{data: to_json(conn.assigns.api_key)})
  end

  @doc """
  POST /stac/api/v1/key/rotate
  """
  def rotate(conn, _params) do
    case ApiKey.rotate_secret_by_owner(conn.assigns.api_key) do
      {:ok, updated, raw_secret} ->
        json(conn, %{
          success: true,
          message:
            "API key rotated successfully. Store the new key now; " <>
              "it cannot be shown again, and the old one no longer works.",
          data: Map.put(to_json(updated), :key, raw_secret)
        })

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{
          error: "Too many requests",
          message: "A key can rotate itself once per hour. Try again later or ask the admin."
        })

      {:error, :stale} ->
        unauthorized(conn, "This key was rotated in the meantime")
    end
  end

  # 401 without a valid issued key, 404 for the static env keys.
  defp require_issued_key(conn, _opts) do
    case conn.assigns do
      %{authenticated: true, api_key: %ApiKey{}} ->
        conn

      %{authenticated: true} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "Not found",
          message:
            "The static API keys are not personal keys, so there is no key to show or rotate"
        })
        |> halt()

      _ ->
        conn |> unauthorized("Missing or invalid X-API-Key") |> halt()
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Unauthorized", message: message})
  end

  # Only the key's own, non-secret data; `contact` and `note` stay admin-only.
  defp to_json(%ApiKey{} = api_key) do
    %{
      name: api_key.name,
      role: api_key.role,
      key_prefix: api_key.key_prefix,
      expires_at: api_key.expires_at,
      rotated_at: api_key.rotated_at,
      secret_expires_at: ApiKey.secret_expires_at(api_key),
      last_used_at: api_key.last_used_at
    }
  end
end
