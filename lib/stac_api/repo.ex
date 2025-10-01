defmodule StacApi.Repo do
  use Ecto.Repo,
    otp_app: :stac_api,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_, opts) do
    {:ok, Keyword.put(opts, :types, StacApi.PostgresTypes)}
  end
end
