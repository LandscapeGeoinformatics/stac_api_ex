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
  @manage "/stac/manage/v1"
  @public "/stac/api/v1"

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

  # A fresh connection authenticated with `secret`.
  defp with_key(secret),
    do: put_req_header(Phoenix.ConnTest.build_conn(), "x-api-key", secret)

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

  describe "max-age of a secret" do
    setup %{conn: conn} do
      previous = Application.get_env(:stac_api, :api_key_max_age_days)
      on_exit(fn -> Application.put_env(:stac_api, :api_key_max_age_days, previous) end)

      post(conn, "#{@manage}/catalogs", %{
        "id" => "aged-catalog",
        "title" => "Aged Catalog",
        "description" => "d",
        "private" => true
      })

      post(conn, "#{@manage}/collections", %{
        "id" => "aged-collection",
        "title" => "Aged Collection",
        "description" => "d",
        "license" => "CC-BY-4.0",
        "catalog_id" => "aged-catalog"
      })

      :ok
    end

    defp set_max_age(days), do: Application.put_env(:stac_api, :api_key_max_age_days, days)

    defp collection_ids(conn) do
      conn
      |> get("#{@public}/collections")
      |> json_response(200)
      |> Map.fetch!("collections")
      |> Enum.map(& &1["id"])
    end

    test "is off by default: an old secret keeps working", %{conn: conn} do
      set_max_age(nil)
      {id, secret} = create_key!(conn, "ancient")
      issued_ago!(id, 1000 * 86_400)

      assert ApiKey.get_by_secret(secret).id == id
      assert "aged-collection" in collection_ids(with_key(secret))
    end

    test "a secret older than the max-age is rejected on every path", %{conn: conn} do
      set_max_age(30)
      {id, ro} = create_key!(conn, "aged-ro")
      {rw_id, rw} = create_key!(conn, "aged-rw", %{"role" => "read_write"})

      assert "aged-collection" in collection_ids(with_key(ro))

      issued_ago!(id, 31 * 86_400)
      issued_ago!(rw_id, 31 * 86_400)

      # Public API: anonymous, so the private collection is hidden.
      refute "aged-collection" in collection_ids(with_key(ro))
      refute "aged-collection" in collection_ids(with_key(rw))

      # Management API: 401.
      assert json_response(post(with_key(rw), "#{@manage}/catalogs", %{"id" => "x"}), 401)

      # Browse unlock: refused.
      locked =
        Phoenix.ConnTest.build_conn()
        |> post(~p"/stac/web/auth", %{"api_key" => rw, "return_to" => "/stac/web/browse"})

      assert get_session(locked, :browse_authenticated) != true
    end

    test "a secret younger than the max-age still works", %{conn: conn} do
      set_max_age(30)
      {id, secret} = create_key!(conn, "young")
      issued_ago!(id, 29 * 86_400)

      assert ApiKey.get_by_secret(secret).id == id
    end

    test "the admin rotate brings an aged-out key back", %{conn: conn} do
      set_max_age(30)
      {id, old_secret} = create_key!(conn, "renewed-by-admin")
      issued_ago!(id, 31 * 86_400)
      assert ApiKey.get_by_secret(old_secret) == nil

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      assert ApiKey.get_by_secret(resp["data"]["key"]).id == id
      assert ApiKey.get_by_secret(old_secret) == nil
    end

    test "a key without max-age or expiry has no secret_expires_at", %{conn: conn} do
      set_max_age(nil)
      {id, _} = create_key!(conn, "unlimited")

      assert ApiKey.secret_expires_at(Repo.get!(ApiKey, id)) == nil
    end

    test "secret_expires_at is the earlier of expires_at and rotated_at + max-age",
         %{conn: conn} do
      {id, _} = create_key!(conn, "min-rule", %{"expires_at" => future(10 * 86_400)})
      key = Repo.get!(ApiKey, id)

      # Only expires_at applies.
      set_max_age(nil)
      assert DateTime.compare(ApiKey.secret_expires_at(key), key.expires_at) == :eq

      # Max-age ends later than expires_at -> expires_at wins.
      set_max_age(30)
      assert DateTime.compare(ApiKey.secret_expires_at(key), key.expires_at) == :eq

      # Max-age ends earlier than expires_at -> max-age wins.
      set_max_age(5)
      expected = DateTime.add(key.rotated_at, 5 * 86_400, :second)
      assert DateTime.compare(ApiKey.secret_expires_at(key), expected) == :eq

      # Only the max-age applies.
      {id2, _} = create_key!(conn, "max-age-only")
      key2 = Repo.get!(ApiKey, id2)
      expected2 = DateTime.add(key2.rotated_at, 5 * 86_400, :second)
      assert DateTime.compare(ApiKey.secret_expires_at(key2), expected2) == :eq
    end
  end
end
