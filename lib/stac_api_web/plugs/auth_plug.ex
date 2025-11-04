defmodule StacApiWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for protecting create/update/delete endpoints.
  Requires API key via X-API-Key header. The API key is hashed and compared
  against the hash stored in environment variable STAC_API_KEY_HASH.
  """
  
  import Plug.Conn

  @doc """
  Get the API key hash from application configuration (set from environment variable)
  """
  defp get_api_key_hash do
    Application.get_env(:stac_api, :api_key_hash) ||
      raise """
      STAC_API_KEY_HASH environment variable is missing.
      Set it to the SHA256 hash of your API key.
      You can generate it with: echo -n "your-api-key" | shasum -a 256
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
      # Hash the provided API key and compare with stored hash
      provided_hash = hash_api_key(api_key)
      stored_hash = get_api_key_hash()
      
      if secure_compare(provided_hash, stored_hash) do
        :ok
      else
        {:error, "Invalid API key"}
      end
    end
  end

  @doc """
  Hash the API key using SHA256
  """
  defp hash_api_key(api_key) do
    :crypto.hash(:sha256, api_key)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Secure comparison to prevent timing attacks
  """
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end
  
  defp secure_compare(_, _), do: false
end
