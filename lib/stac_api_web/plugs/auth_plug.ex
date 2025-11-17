defmodule StacApiWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for protecting create/update/delete endpoints.
  Requires API key via X-API-Key header. The API key is compared in plain text
  against the key stored in environment variable STAC_API_KEY.
  """
  
  import Plug.Conn

  @doc """
  Get the API key from application configuration (set from environment variable)
  """
  defp get_api_key do
    Application.get_env(:stac_api, :api_key) ||
      raise """
      STAC_API_KEY environment variable is missing.
      Set it to your API key for authentication.
      """
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate(conn) do
      :ok ->
        conn

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized", message: reason}))
        |> halt()
    end
  end

  defp authenticate(conn) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()
    
    if is_nil(api_key) || api_key == "" do
      {:error, "Missing X-API-Key header"}
    else
      # Compare provided API key with stored API key using secure comparison
      stored_api_key = get_api_key()
      
      if secure_compare(api_key, stored_api_key) do
        :ok
      else
        {:error, "Invalid API key"}
      end
    end
  end

  @doc """
  Secure comparison to prevent timing attacks
  """
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end
  
  defp secure_compare(_, _), do: false
end
