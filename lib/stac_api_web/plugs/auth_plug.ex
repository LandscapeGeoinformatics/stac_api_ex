defmodule StacApiWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for write endpoints (POST, PUT, PATCH, DELETE).
  Requires read-write API key via X-API-Key header.
  """
  
  import Plug.Conn

  defp get_api_keys do
    Application.get_env(:stac_api, :api_keys) ||
      raise """
      API keys configuration is missing.
      Set STAC_API_KEY and STAC_API_KEY_RO environment variables.
      """
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate_rw(conn) do
      {:ok, :read_write} ->
        conn
        |> assign(:auth_level, :read_write)
        |> assign(:authenticated, true)

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized", message: reason}))
        |> halt()
    end
  end

  defp authenticate_rw(conn) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    
    if is_nil(api_key) || api_key == "" do
      {:error, "Missing X-API-Key header"}
    else
      %{read_write: rw_keys} = get_api_keys()
      
      if Enum.any?(rw_keys, &secure_compare(api_key, &1)) do
        {:ok, :read_write}
      else
        {:error, "Invalid API key. Write operations require read-write (RW) key"}
      end
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end
  
  defp secure_compare(_, _), do: false
end