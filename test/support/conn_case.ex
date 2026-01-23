defmodule StacApiWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use StacApiWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint StacApiWeb.Endpoint

      use StacApiWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import StacApiWeb.ConnCase

      alias StacApi.Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(StacApi.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    
    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end

  @doc """
  Setup helper that adds authentication headers to the connection.
  """
  def authenticated_conn(conn) do
    api_key = Application.get_env(:stac_api, :api_keys)[:read_write] |> List.first()
    Plug.Conn.put_req_header(conn, "x-api-key", api_key)
  end

  @doc """
  Setup helper that adds read-only authentication headers to the connection.
  """
  def read_only_conn(conn) do
    api_key = Application.get_env(:stac_api, :api_keys)[:read_only] |> List.first()
    Plug.Conn.put_req_header(conn, "x-api-key", api_key)
  end
end
