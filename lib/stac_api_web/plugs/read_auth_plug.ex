defmodule StacApiWeb.Plugs.ReadAuthPlug do
  @moduledoc """
  Optional authentication plug for read endpoints.
  Checks for read-only or read-write API key via X-API-Key header.
  Sets authentication context without blocking requests.

  A key is accepted if it matches, in order:

    1. a static read-write key (`STAC_API_KEY`) -> `:read_write`
    2. a static read-only key (`STAC_API_KEY_RO`) -> `:read_only`
    3. a personalized key issued through the API key management endpoints
       (stored hashed in the `api_keys` table, see `StacApi.Data.ApiKey`)
       -> `:read_only`; each use refreshes the key's `last_used_at`

  Assigns on the conn:

    * `:auth_level` - `:read_write`, `:read_only`, or `nil`
    * `:authenticated` - `true` or `false`

  A missing or invalid key never halts the request; it just leaves the conn
  unauthenticated so public content is still served.
  """

  import Plug.Conn

  alias StacApi.Data.ApiKey

  defp get_api_keys do
    Application.get_env(:stac_api, :api_keys) ||
      raise """
      API keys configuration is missing.
      Set STAC_API_KEY and STAC_API_KEY_RO environment variables.
      """
  end

  @doc "Plug callback; no options are used."
  def init(opts), do: opts

  @doc """
  Reads the `x-api-key` header and assigns `:auth_level` and `:authenticated`
  on the conn. Never halts the request.
  """
  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, :read_write} ->
        conn
        |> assign(:auth_level, :read_write)
        |> assign(:authenticated, true)

      {:ok, :read_only} ->
        conn
        |> assign(:auth_level, :read_only)
        |> assign(:authenticated, true)

      {:error, _reason} ->
        conn
        |> assign(:auth_level, nil)
        |> assign(:authenticated, false)
    end
  end

  defp authenticate(conn) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()

    if is_nil(api_key) || api_key == "" do
      {:error, "No API key provided"}
    else
      %{read_write: rw_keys, read_only: ro_keys} = get_api_keys()

      cond do
        Enum.any?(rw_keys, &secure_compare(api_key, &1)) ->
          {:ok, :read_write}

        Enum.any?(ro_keys, &secure_compare(api_key, &1)) ->
          {:ok, :read_only}

        issued_key_valid?(api_key) ->
          {:ok, :read_only}

        true ->
          {:error, "Invalid API key"}
      end
    end
  end

  # Returns true if `api_key` belongs to a personalized key issued via
  # /stac/manage/v1/api-keys, and records the use (throttled to once an hour).
  # Issued keys only ever grant read access.
  defp issued_key_valid?(api_key) do
    case ApiKey.get_by_secret(api_key) do
      nil ->
        false

      issued ->
        ApiKey.touch_last_used(issued)
        true
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(_, _), do: false
end
