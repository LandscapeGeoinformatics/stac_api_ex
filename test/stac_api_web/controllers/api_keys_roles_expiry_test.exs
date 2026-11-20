defmodule StacApiWeb.ApiKeysRolesExpiryTest do
  @moduledoc """
  Roles, expiry, contact and note of issued API keys (#18): what a read-only
  and a read-write key may do, that only the static RW key manages keys, and
  that an expired key is invalid everywhere.
  """
  use StacApiWeb.ConnCase, async: false

  import Ecto.Query

  alias StacApi.Data.ApiKey
  alias StacApiWeb.Plugs.{AuthPlug, ReadAuthPlug}

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

  # A fresh connection authenticated with `secret`.
  defp with_key(secret),
    do: put_req_header(Phoenix.ConnTest.build_conn(), "x-api-key", secret)

  # Moves the key's expiry into the past; the API itself refuses to create that.
  defp expire!(id) do
    past = DateTime.add(DateTime.utc_now(), -60, :second)
    Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [expires_at: past])
  end

  defp future, do: DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()
  defp past, do: DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_iso8601()

  describe "creating keys" do
    test "defaults to a read-only key with a stac_ro_ secret", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => "default-role"}) |> json_response(201)

      assert resp["data"]["role"] == "read_only"
      assert "stac_ro_" <> _ = resp["data"]["key"]
      assert resp["data"]["expires_at"] == nil
      assert resp["data"]["contact"] == nil
      assert resp["data"]["note"] == nil
    end

    test "a read-write key gets a stac_rw_ secret and prefix", %{conn: conn} do
      resp =
        conn
        |> post(@path, %{"name" => "writer", "role" => "read_write"})
        |> json_response(201)

      assert resp["data"]["role"] == "read_write"
      assert "stac_rw_" <> _ = resp["data"]["key"]
      assert String.starts_with?(resp["data"]["key_prefix"], "stac_rw_")
    end

    test "stores expires_at, contact and note and returns them in show and list", %{conn: conn} do
      expires_at = future()

      {id, _} =
        create_key!(conn, "student", %{
          "role" => "read_write",
          "expires_at" => expires_at,
          "contact" => "student@example.org",
          "note" => "Thesis project, until end of semester"
        })

      shown = conn |> get("#{@path}/#{id}") |> json_response(200)
      listed = conn |> get(@path) |> json_response(200)
      from_list = Enum.find(listed["data"], &(&1["id"] == id))

      for data <- [shown["data"], from_list] do
        assert data["role"] == "read_write"
        assert data["contact"] == "student@example.org"
        assert data["note"] == "Thesis project, until end of semester"
        assert {:ok, parsed, 0} = DateTime.from_iso8601(data["expires_at"])
        assert DateTime.compare(parsed, DateTime.from_iso8601(expires_at) |> elem(1)) == :eq
        refute Map.has_key?(data, "key")
      end
    end

    test "rejects an unknown role", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => "root", "role" => "admin"}) |> json_response(422)
      assert resp["details"]["role"] == ["is invalid"]
    end

    test "rejects an expires_at in the past", %{conn: conn} do
      resp =
        conn
        |> post(@path, %{"name" => "already-over", "expires_at" => past()})
        |> json_response(422)

      assert resp["details"]["expires_at"] == ["must be in the future"]
    end

    test "rejects an expires_at without a UTC offset instead of guessing UTC", %{conn: conn} do
      for value <- [
            "2099-02-28T23:59:59",
            "2099-02-28T23:59",
            "2099-02-28 23:59:59",
            "2099-02-28"
          ] do
        resp =
          conn
          |> post(@path, %{"name" => "no-offset", "expires_at" => value})
          |> json_response(422)

        assert [message] = resp["details"]["expires_at"], "for #{value}"
        assert message =~ "UTC offset" or message == "is invalid", "for #{value}"
      end

      assert Repo.aggregate(from(k in ApiKey, where: k.name == "no-offset"), :count) == 0
    end

    test "accepts Z and numeric offsets and stores the instant in UTC", %{conn: conn} do
      for {name, value, utc} <- [
            {"z", "2099-02-28T23:59:59Z", "2099-02-28T23:59:59"},
            {"plus-two", "2099-03-01T01:59:59+02:00", "2099-02-28T23:59:59"},
            {"minus-five", "2099-02-28T18:59:59-05:00", "2099-02-28T23:59:59"},
            {"fraction", "2099-02-28T23:59:59.500Z", "2099-02-28T23:59:59"}
          ] do
        resp = conn |> post(@path, %{"name" => name, "expires_at" => value}) |> json_response(201)

        assert String.starts_with?(resp["data"]["expires_at"], utc), "for #{value}"
      end
    end

    test "rejects an expires_at that is not a timestamp", %{conn: conn} do
      resp =
        conn
        |> post(@path, %{"name" => "garbage", "expires_at" => "next semester"})
        |> json_response(422)

      assert resp["details"]["expires_at"] == ["is invalid"]
    end
  end

  describe "PATCH /api-keys/:id" do
    test "edits expires_at, contact and note and leaves the rest alone", %{conn: conn} do
      {id, secret} = create_key!(conn, "editable", %{"role" => "read_write"})
      expires_at = future()

      resp =
        conn
        |> patch("#{@path}/#{id}", %{
          "expires_at" => expires_at,
          "contact" => "owner@example.org",
          "note" => "now with a note"
        })
        |> json_response(200)

      assert resp["data"]["name"] == "editable"
      assert resp["data"]["role"] == "read_write"
      assert resp["data"]["contact"] == "owner@example.org"
      assert resp["data"]["note"] == "now with a note"
      assert resp["data"]["expires_at"] != nil
      assert ApiKey.get_by_secret(secret).id == id
    end

    test "expires_at can be cleared again", %{conn: conn} do
      {id, _} = create_key!(conn, "clearable", %{"expires_at" => future()})

      resp = conn |> patch("#{@path}/#{id}", %{"expires_at" => nil}) |> json_response(200)
      assert resp["data"]["expires_at"] == nil
    end

    test "null clears contact and note, a missing key leaves them alone", %{conn: conn} do
      {id, _} =
        create_key!(conn, "null-vs-missing", %{
          "expires_at" => future(),
          "contact" => "owner@example.org",
          "note" => "keep me"
        })

      # Only `contact` is sent: `note` and `expires_at` are missing, so they stay.
      resp = conn |> patch("#{@path}/#{id}", %{"contact" => nil}) |> json_response(200)
      assert resp["data"]["contact"] == nil
      assert resp["data"]["note"] == "keep me"
      assert resp["data"]["expires_at"] != nil

      # Now `note` is cleared and `contact` (missing) stays cleared.
      resp = conn |> patch("#{@path}/#{id}", %{"note" => nil}) |> json_response(200)
      assert resp["data"]["note"] == nil
      assert resp["data"]["contact"] == nil
      assert resp["data"]["expires_at"] != nil
    end

    test "PATCH {} changes nothing, not even updated_at", %{conn: conn} do
      {id, _} =
        create_key!(conn, "no-op", %{
          "expires_at" => future(),
          "contact" => "owner@example.org",
          "note" => "unchanged"
        })

      # Put updated_at far enough back that any touch would be visible.
      old = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [updated_at: old])
      before = Repo.get!(ApiKey, id)

      resp = conn |> patch("#{@path}/#{id}", %{}) |> json_response(200)

      assert resp["data"]["name"] == "no-op"
      assert resp["data"]["contact"] == "owner@example.org"
      assert resp["data"]["note"] == "unchanged"
      assert Repo.get!(ApiKey, id).updated_at == before.updated_at
      assert DateTime.compare(before.updated_at, old) == :eq
    end

    test "rejects a null or empty name and keeps the old one", %{conn: conn} do
      {id, _} = create_key!(conn, "keep-my-name")

      for name <- [nil, "", "   "] do
        resp = conn |> patch("#{@path}/#{id}", %{"name" => name}) |> json_response(422)
        assert resp["details"]["name"] != nil
      end

      assert Repo.get!(ApiKey, id).name == "keep-my-name"
    end

    test "rejects an expires_at without a UTC offset and keeps the old one", %{conn: conn} do
      {id, _} = create_key!(conn, "patch-no-offset", %{"expires_at" => future()})
      before = Repo.get!(ApiKey, id).expires_at

      resp =
        conn
        |> patch("#{@path}/#{id}", %{"expires_at" => "2099-02-28T23:59:59"})
        |> json_response(422)

      assert [message] = resp["details"]["expires_at"]
      assert message =~ "UTC offset"
      assert DateTime.compare(Repo.get!(ApiKey, id).expires_at, before) == :eq

      ok =
        conn
        |> patch("#{@path}/#{id}", %{"expires_at" => "2099-03-01T01:59:59+02:00"})
        |> json_response(200)

      assert String.starts_with?(ok["data"]["expires_at"], "2099-02-28T23:59:59")
    end

    test "rejects an expires_at in the past", %{conn: conn} do
      {id, _} = create_key!(conn, "too-late")

      resp = conn |> patch("#{@path}/#{id}", %{"expires_at" => past()}) |> json_response(422)
      assert resp["details"]["expires_at"] == ["must be in the future"]
    end

    test "rejects a role change with 422 and keeps the role", %{conn: conn} do
      {id, secret} = create_key!(conn, "stays-read-only")

      resp =
        conn
        |> patch("#{@path}/#{id}", %{"role" => "read_write", "name" => "renamed"})
        |> json_response(422)

      assert [message] = resp["details"]["role"]
      assert message =~ "cannot be changed"

      unchanged = conn |> get("#{@path}/#{id}") |> json_response(200)
      assert unchanged["data"]["role"] == "read_only"
      assert unchanged["data"]["name"] == "stays-read-only"
      assert ApiKey.auth_level(ApiKey.get_by_secret(secret)) == :read_only
    end
  end

  describe "rotate" do
    test "keeps the role, so the new secret has the matching prefix", %{conn: conn} do
      {id, old_secret} = create_key!(conn, "rotating-rw", %{"role" => "read_write"})

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      assert "stac_rw_" <> _ = resp["data"]["key"]
      assert resp["data"]["role"] == "read_write"
      assert ApiKey.get_by_secret(old_secret) == nil
    end

    test "returns expires_at and does not move it", %{conn: conn} do
      {id, _} = create_key!(conn, "rotating-with-expiry", %{"expires_at" => future()})
      before = Repo.get!(ApiKey, id).expires_at

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      assert {:ok, returned, 0} = DateTime.from_iso8601(resp["data"]["expires_at"])
      assert DateTime.compare(returned, before) == :eq
      assert DateTime.compare(Repo.get!(ApiKey, id).expires_at, before) == :eq
    end

    test "an expired key can be rotated but stays expired until its expires_at is patched",
         %{conn: conn} do
      {id, _} = create_key!(conn, "expired-rotate", %{"expires_at" => future()})
      expire!(id)
      expired_at = Repo.get!(ApiKey, id).expires_at

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)
      new_secret = resp["data"]["key"]

      # Rotation does not bring the key back and reports the unchanged expiry.
      assert {:ok, returned, 0} = DateTime.from_iso8601(resp["data"]["expires_at"])
      assert DateTime.compare(returned, expired_at) == :eq
      assert ApiKey.get_by_secret(new_secret) == nil

      # The admin revives it by moving expires_at to the future.
      conn |> patch("#{@path}/#{id}", %{"expires_at" => future()}) |> json_response(200)
      assert ApiKey.get_by_secret(new_secret).id == id
    end
  end

  describe "an issued read-write key" do
    setup %{conn: conn} do
      {_id, secret} = create_key!(conn, "rw-writer", %{"role" => "read_write"})
      {:ok, rw: with_key(secret)}
    end

    test "can create, update and delete a catalog, a collection and an item", %{rw: rw} do
      catalog = %{"id" => "rw-catalog", "title" => "RW Catalog", "description" => "d"}
      assert json_response(post(rw, "#{@manage}/catalogs", catalog), 201)
      assert json_response(patch(rw, "#{@manage}/catalogs/rw-catalog", %{"title" => "T2"}), 200)

      collection = %{
        "id" => "rw-collection",
        "title" => "RW Collection",
        "description" => "d",
        "license" => "CC-BY-4.0",
        "catalog_id" => "rw-catalog"
      }

      assert json_response(post(rw, "#{@manage}/collections", collection), 201)

      assert json_response(
               patch(rw, "#{@manage}/collections/rw-collection", %{"title" => "C2"}),
               200
             )

      item = %{
        "id" => "rw-item",
        "collection_id" => "rw-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "properties" => %{"datetime" => "2024-01-01T12:00:00Z"}
      }

      assert json_response(post(rw, "#{@manage}/items", item), 201)

      patched = %{"id" => "rw-item", "properties" => %{"datetime" => "2024-01-02T12:00:00Z"}}
      assert json_response(patch(rw, "#{@manage}/items/rw-item", patched), 200)

      assert json_response(delete(rw, "#{@manage}/items/rw-item"), 200)
      assert json_response(delete(rw, "#{@manage}/collections/rw-collection"), 200)
      assert json_response(delete(rw, "#{@manage}/catalogs/rw-catalog"), 200)
    end

    test "gets 401 on every /api-keys endpoint", %{conn: conn, rw: rw} do
      {id, _} = create_key!(conn, "target")

      assert json_response(get(rw, @path), 401)
      assert json_response(get(rw, "#{@path}/#{id}"), 401)
      assert json_response(post(rw, @path, %{"name" => "minted", "role" => "read_write"}), 401)
      assert json_response(patch(rw, "#{@path}/#{id}", %{"note" => "x"}), 401)
      assert json_response(post(rw, "#{@path}/#{id}/rotate"), 401)
      assert json_response(delete(rw, "#{@path}/#{id}"), 401)

      # nothing happened
      assert conn |> get("#{@path}/#{id}") |> json_response(200)
    end

    test "AuthPlug assigns the issued key and refreshes last_used_at", %{conn: conn} do
      {id, secret} = create_key!(conn, "tracked-writer", %{"role" => "read_write"})
      assert Repo.get!(ApiKey, id).last_used_at == nil

      plugged = secret |> with_key() |> AuthPlug.call([])

      assert plugged.assigns.auth_level == :read_write
      assert plugged.assigns.api_key.id == id
      assert %DateTime{} = Repo.get!(ApiKey, id).last_used_at
    end

    test "the static RW key still works and assigns no api_key", %{conn: conn} do
      plugged = AuthPlug.call(conn, [])
      assert plugged.assigns.auth_level == :read_write
      assert plugged.assigns.api_key == nil
    end
  end

  describe "an issued read-only key" do
    setup %{conn: conn} do
      {_id, secret} = create_key!(conn, "ro-reader")
      {:ok, ro: with_key(secret)}
    end

    test "gets 401 on the data write endpoints", %{ro: ro} do
      catalog = %{"id" => "ro-catalog", "title" => "t", "description" => "d"}

      assert json_response(post(ro, "#{@manage}/catalogs", catalog), 401)
      assert json_response(patch(ro, "#{@manage}/catalogs/any", %{"title" => "t"}), 401)
      assert json_response(delete(ro, "#{@manage}/catalogs/any"), 401)
      assert json_response(post(ro, "#{@manage}/collections", %{"id" => "c"}), 401)
      assert json_response(delete(ro, "#{@manage}/collections/any"), 401)
      assert json_response(post(ro, "#{@manage}/items", %{"id" => "i"}), 401)
      assert json_response(post(ro, "#{@manage}/items/import", %{}), 401)
      assert json_response(delete(ro, "#{@manage}/items/any"), 401)
    end

    test "ReadAuthPlug assigns the issued key", %{ro: ro} do
      plugged = ReadAuthPlug.call(ro, [])
      assert plugged.assigns.auth_level == :read_only
      assert %ApiKey{role: "read_only"} = plugged.assigns.api_key
    end
  end

  describe "an expired key" do
    test "is anonymous on the public API", %{conn: conn} do
      for role <- ["read_only", "read_write"] do
        {id, secret} = create_key!(conn, "expired-public-#{role}", %{"role" => role})
        expire!(id)

        plugged = secret |> with_key() |> ReadAuthPlug.call([])

        assert plugged.assigns.authenticated == false
        assert plugged.assigns.auth_level == nil
        assert plugged.assigns.api_key == nil
        assert json_response(get(with_key(secret), "#{@public}/collections"), 200)
      end
    end

    test "gets 401 on the management API", %{conn: conn} do
      {id, secret} = create_key!(conn, "expired-writer", %{"role" => "read_write"})
      assert json_response(get(with_key(secret), "#{@manage}/catalogs"), 200)

      expire!(id)

      assert json_response(get(with_key(secret), "#{@manage}/catalogs"), 401)
      assert json_response(get(with_key(secret), @path), 401)
    end

    test "does not unlock the browser", %{conn: conn} do
      for role <- ["read_only", "read_write"] do
        {id, secret} = create_key!(conn, "expired-browser-#{role}", %{"role" => role})
        expire!(id)

        locked =
          Phoenix.ConnTest.build_conn()
          |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

        assert get_session(locked, :browse_authenticated) != true
      end
    end

    test "can be extended again by the admin", %{conn: conn} do
      {id, secret} = create_key!(conn, "renewed", %{"role" => "read_write"})
      expire!(id)
      assert ApiKey.get_by_secret(secret) == nil

      conn |> patch("#{@path}/#{id}", %{"expires_at" => future()}) |> json_response(200)
      assert ApiKey.get_by_secret(secret).id == id
    end
  end

  describe "browse unlock" do
    test "an issued read-write key unlocks at the read_write level", %{conn: conn} do
      {_id, secret} = create_key!(conn, "browser-writer", %{"role" => "read_write"})

      unlocked =
        Phoenix.ConnTest.build_conn()
        |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

      assert get_session(unlocked, :browse_authenticated) == true
      assert get_session(unlocked, :browse_auth_level) == :read_write
    end

    test "an issued read-only key unlocks at the read_only level", %{conn: conn} do
      {_id, secret} = create_key!(conn, "browser-reader")

      unlocked =
        Phoenix.ConnTest.build_conn()
        |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

      assert get_session(unlocked, :browse_auth_level) == :read_only
    end

    test "unlocking refreshes last_used_at", %{conn: conn} do
      {id, secret} = create_key!(conn, "browser-only")
      assert Repo.get!(ApiKey, id).last_used_at == nil

      Phoenix.ConnTest.build_conn()
      |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

      assert %DateTime{} = Repo.get!(ApiKey, id).last_used_at
    end
  end

  describe "private catalog" do
    setup %{conn: conn} do
      post(conn, "#{@manage}/catalogs", %{
        "id" => "secret-catalog",
        "title" => "Secret Catalog",
        "description" => "d",
        "private" => true
      })

      post(conn, "#{@manage}/collections", %{
        "id" => "secret-collection",
        "title" => "Secret Collection",
        "description" => "d",
        "license" => "CC-BY-4.0",
        "catalog_id" => "secret-catalog"
      })

      :ok
    end

    defp collection_ids(conn) do
      conn
      |> get("#{@public}/collections")
      |> json_response(200)
      |> Map.fetch!("collections")
      |> Enum.map(& &1["id"])
    end

    test "is hidden without a key, visible with an issued RO and RW key, hidden once expired",
         %{conn: conn} do
      {ro_id, ro} = create_key!(conn, "private-ro")
      {rw_id, rw} = create_key!(conn, "private-rw", %{"role" => "read_write"})

      refute "secret-collection" in collection_ids(Phoenix.ConnTest.build_conn())
      assert "secret-collection" in collection_ids(with_key(ro))
      assert "secret-collection" in collection_ids(with_key(rw))

      expire!(ro_id)
      expire!(rw_id)

      refute "secret-collection" in collection_ids(with_key(ro))
      refute "secret-collection" in collection_ids(with_key(rw))
    end
  end
end
