defmodule StacApiWeb.Plugs.ReadAuthPlug do
  @moduledoc """
  Optional authentication plug for read endpoints.
  Checks for read-only or read-write API key via X-API-Key header.
  Sets authentication context without blocking requests.
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
        
        true ->
          {:error, "Invalid API key"}
      end
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end
  
  defp secure_compare(_, _), do: false
end
