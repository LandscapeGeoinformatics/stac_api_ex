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
       -> `:read_write` or `:read_only` according to the key's role; each use
       refreshes the key's `last_used_at`. An expired key is not accepted.

  Assigns on the conn:

    * `:auth_level` - `:read_write`, `:read_only`, or `nil`
    * `:authenticated` - `true` or `false`
    * `:api_key` - the issued `StacApi.Data.ApiKey`, or `nil` for a static
      key or no key

  A missing or invalid key never halts the request; it just leaves the conn
  unauthenticated so public content is still served.
  """

  import Plug.Conn

  alias StacApi.Data.ApiKey
  alias StacApi.StaticKeys

  @doc "Plug callback; no options are used."
  def init(opts), do: opts

  @doc """
  Reads the `x-api-key` header and assigns `:auth_level` and `:authenticated`
  on the conn. Never halts the request.
  """
  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, level, api_key} ->
        conn
        |> assign(:auth_level, level)
        |> assign(:authenticated, true)
        |> assign(:api_key, api_key)

      {:error, _reason} ->
        conn
        |> assign(:auth_level, nil)
        |> assign(:authenticated, false)
        |> assign(:api_key, nil)
    end
  end

  defp authenticate(conn) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()

    if is_nil(api_key) || api_key == "" do
      {:error, "No API key provided"}
    else
      cond do
        level = StaticKeys.level(api_key) ->
          {:ok, level, nil}

        issued = issued_key(api_key) ->
          {:ok, ApiKey.auth_level(issued), issued}

        true ->
          {:error, "Invalid API key"}
      end
    end
  end

  # The unexpired issued key (see /stac/manage/v1/api-keys) for `api_key`, or
  # nil. Records the use (throttled to once an hour).
  defp issued_key(api_key) do
    with %ApiKey{} = issued <- ApiKey.get_by_secret(api_key) do
      ApiKey.touch_last_used(issued)
      issued
    end
  end
end
