defmodule StacApiWeb.ApiKeysSelfServiceTest do
  @moduledoc """
  Step 3 of the personal API keys (#19): `rotated_at` / `rotated_by`, the
  optional max-age of a secret, and the self-service `GET /key` and
  `POST /key/rotate` endpoints.
  """
  use StacApiWeb.ConnCase, async: false

  import Ecto.Query

  alias StacApi.Data.ApiKey

  @path "/stac/manage/v1/api-keys"

  setup %{conn: conn} do
    {:ok, conn: authenticated_conn(conn)}
  end

  # Creates a key through the API (as the static RW key) and returns
  # `{id, raw_secret}`.
  defp create_key!(conn, name, extra \\ %{}) do
    resp = conn |> post(@path, Map.put(extra, "name", name)) |> json_response(201)
    {resp["data"]["id"], resp["data"]["key"]}
  end

  defp future(seconds \\ 86_400),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.to_iso8601()

  # Pretends the current secret was issued `seconds` ago.
  defp issued_ago!(id, seconds) do
    at = DateTime.add(DateTime.utc_now(), -seconds, :second)
    Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [rotated_at: at])
  end

  describe "rotated_at and rotated_by" do
    test "a new key has rotated_at set and was never rotated", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => "fresh"}) |> json_response(201)

      assert {:ok, rotated_at, 0} = DateTime.from_iso8601(resp["data"]["rotated_at"])
      assert abs(DateTime.diff(DateTime.utc_now(), rotated_at)) < 60
      assert resp["data"]["rotated_by"] == nil
    end

    test "the admin listing shows rotated_at and rotated_by", %{conn: conn} do
      {id, _} = create_key!(conn, "listed")
      conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      listed = conn |> get(@path) |> json_response(200)
      shown = conn |> get("#{@path}/#{id}") |> json_response(200)
      from_list = Enum.find(listed["data"], &(&1["id"] == id))

      for data <- [from_list, shown["data"]] do
        assert data["rotated_by"] == "admin"
        assert {:ok, _, 0} = DateTime.from_iso8601(data["rotated_at"])
      end
    end

    test "the admin rotate records rotated_by admin and a new rotated_at", %{conn: conn} do
      {id, old_secret} = create_key!(conn, "admin-rotated")
      issued_ago!(id, 7200)
      before = Repo.get!(ApiKey, id).rotated_at

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      after_rotate = Repo.get!(ApiKey, id)
      assert after_rotate.rotated_by == "admin"
      assert DateTime.compare(after_rotate.rotated_at, before) == :gt
      assert ApiKey.get_by_secret(old_secret) == nil
      assert ApiKey.get_by_secret(resp["data"]["key"]).id == id
    end

    test "the admin rotate changes only the secret and the rotation info", %{conn: conn} do
      {id, _} =
        create_key!(conn, "only-the-secret", %{
          "role" => "read_write",
          "expires_at" => future(),
          "contact" => "owner@example.org",
          "note" => "stays"
        })

      before = Repo.get!(ApiKey, id)
      conn |> post("#{@path}/#{id}/rotate") |> json_response(200)
      after_rotate = Repo.get!(ApiKey, id)

      assert after_rotate.key_hash != before.key_hash
      assert after_rotate.key_prefix != before.key_prefix
      assert after_rotate.role == before.role
      assert after_rotate.name == before.name
      assert after_rotate.contact == before.contact
      assert after_rotate.note == before.note
      assert DateTime.compare(after_rotate.expires_at, before.expires_at) == :eq
    end
  end
end
