defmodule StacApiWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for write endpoints (POST, PUT, PATCH, DELETE).
  Requires a read-write API key via X-API-Key header.

  A key is accepted if it is

    1. a static read-write key (`STAC_API_KEY`), or
    2. an issued key with the `read_write` role (see `StacApi.Data.ApiKey`),
       unless the plug is used with `admin_only: true`.

  Use `plug StacApiWeb.Plugs.AuthPlug, admin_only: true` for endpoints that
  only the static read-write key may call (API key management), so an issued
  read-write key can never mint or change keys.

  Assigns on success:

    * `:auth_level` - `:read_write`
    * `:authenticated` - `true`
    * `:api_key` - the issued `StacApi.Data.ApiKey`, or `nil` for a static key

  Responds with 401 and halts otherwise. An expired issued key is invalid.
  """

  import Plug.Conn

  alias StacApi.Data.ApiKey
  alias StacApi.StaticKeys

  @doc "Plug callback; `admin_only: true` restricts access to the static read-write key."
  def init(opts), do: opts

  @doc """
  Checks the `x-api-key` header and assigns `:auth_level`, `:authenticated`
  and `:api_key`, or halts with 401.
  """
  def call(conn, opts) do
    case authenticate_rw(conn, Keyword.get(opts, :admin_only, false)) do
      {:ok, api_key} ->
        conn
        |> assign(:auth_level, :read_write)
        |> assign(:authenticated, true)
        |> assign(:api_key, api_key)

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized", message: reason}))
        |> halt()
    end
  end

  defp authenticate_rw(conn, admin_only) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()

    if is_nil(api_key) || api_key == "" do
      {:error, "Missing X-API-Key header"}
    else
      cond do
        StaticKeys.level(api_key) == :read_write ->
          {:ok, nil}

        admin_only ->
          {:error, "Invalid API key. Key management requires the static read-write key"}

        issued = issued_rw_key(api_key) ->
          {:ok, issued}

        true ->
          {:error, "Invalid API key. Write operations require read-write (RW) key"}
      end
    end
  end

  # An unexpired issued key with the read_write role; records the use.
  defp issued_rw_key(api_key) do
    with %ApiKey{} = issued <- ApiKey.get_by_secret(api_key),
         :read_write <- ApiKey.auth_level(issued) do
      ApiKey.touch_last_used(issued)
      issued
    else
      _ -> nil
    end
  end
end
