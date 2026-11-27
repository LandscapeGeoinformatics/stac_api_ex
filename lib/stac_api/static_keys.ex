defmodule StacApi.StaticKeys do
  @moduledoc """
  The static API keys from the environment: `STAC_API_KEY` (read-write) and
  `STAC_API_KEY_RO` (read-only), kept in `config :stac_api, :api_keys`.

  They are the break-glass access and are not stored in the database, unlike
  the issued keys of `StacApi.Data.ApiKey`. This is the one place that compares
  a presented key with them, used by `StacApiWeb.Plugs.ReadAuthPlug`,
  `StacApiWeb.Plugs.AuthPlug` and the browse unlock, so the rule cannot drift
  apart between them.
  """

  @doc """
  The access level the static key `api_key` grants: `:read_write`,
  `:read_only`, or `nil` when it is none of the static keys (also for a blank
  or non-string value). Compares in constant time. Raises if the keys are not
  configured at all.
  """
  def level(api_key) when is_binary(api_key) and api_key != "" do
    %{read_write: read_write, read_only: read_only} = fetch!()

    cond do
      matches?(api_key, read_write) -> :read_write
      matches?(api_key, read_only) -> :read_only
      true -> nil
    end
  end

  def level(_), do: nil

  defp matches?(api_key, keys) do
    Enum.any?(keys || [], &(is_binary(&1) and Plug.Crypto.secure_compare(api_key, &1)))
  end

  defp fetch! do
    Application.get_env(:stac_api, :api_keys) ||
      raise """
      API keys configuration is missing.
      Set STAC_API_KEY and STAC_API_KEY_RO environment variables.
      """
  end
end
