defmodule StacApiWeb.ApiKeysCrudControllerTest do
  use StacApiWeb.ConnCase, async: false

  import Ecto.Query

  alias StacApi.Data.ApiKey
  alias StacApiWeb.Plugs.ReadAuthPlug

  @path "/stac/manage/v1/api-keys"

  setup %{conn: conn} do
    {:ok, conn: authenticated_conn(conn)}
  end

  # Creates a key through the API and returns `{id, raw_secret}`.
  defp create_key!(conn, name) do
    resp = conn |> post(@path, %{"name" => name}) |> json_response(201)
    {resp["data"]["id"], resp["data"]["key"]}
  end

  # A fresh connection authenticated with `secret` (ignores the setup conn's key).
  defp with_key(_conn, secret), do: put_req_header(Phoenix.ConnTest.build_conn(), "x-api-key", secret)

  describe "authorization" do
    test "management endpoints reject requests without a key" do
      conn = Phoenix.ConnTest.build_conn()
      assert json_response(get(conn, @path), 401)
    end

    test "management endpoints reject the static read-only key" do
      conn = Phoenix.ConnTest.build_conn() |> read_only_conn()
      assert json_response(get(conn, @path), 401)
      assert json_response(post(conn, @path, %{"name" => "x"}), 401)
    end

    test "an issued key cannot manage keys", %{conn: conn} do
      {_id, secret} = create_key!(conn, "cannot-manage")

      issued = with_key(conn, secret)
      assert json_response(get(issued, @path), 401)
      assert json_response(post(issued, @path, %{"name" => "nope"}), 401)
    end
  end

  describe "POST /api-keys" do
    test "creates a key and returns the secret once", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => "ci-pipeline"}) |> json_response(201)

      assert resp["success"] == true
      assert resp["message"] =~ "Store the key now"
      assert resp["data"]["name"] == "ci-pipeline"
      assert resp["data"]["last_used_at"] == nil
      assert "stac_ro_" <> _ = resp["data"]["key"]
      assert String.starts_with?(resp["data"]["key"], resp["data"]["key_prefix"])
    end

    test "stores only the hash, never the raw secret", %{conn: conn} do
      {id, secret} = create_key!(conn, "hash-only")

      stored = Repo.get!(ApiKey, id)
      assert stored.key_hash == ApiKey.hash(secret)
      refute stored.key_hash == secret
    end

    test "trims the name", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => "  padded  "}) |> json_response(201)
      assert resp["data"]["name"] == "padded"
    end

    test "rejects a missing, blank or non-string name", %{conn: conn} do
      for params <- [%{}, %{"name" => ""}, %{"name" => "   "}, %{"name" => 123}] do
        resp = conn |> post(@path, params) |> json_response(422)
        assert resp["error"] == "Validation failed"
        assert Map.has_key?(resp["details"], "name")
      end
    end

    test "rejects a name longer than 100 characters", %{conn: conn} do
      resp = conn |> post(@path, %{"name" => String.duplicate("a", 101)}) |> json_response(422)
      assert resp["details"]["name"] != []
    end

    test "rejects a duplicate name", %{conn: conn} do
      create_key!(conn, "dup-name")
      resp = conn |> post(@path, %{"name" => "dup-name"}) |> json_response(422)
      assert resp["details"]["name"] == ["has already been taken"]
    end
  end

  describe "GET /api-keys" do
    test "lists keys without ever exposing secrets", %{conn: conn} do
      {id, secret} = create_key!(conn, "listed")

      body = conn |> get(@path) |> json_response(200)
      entry = Enum.find(body["data"], &(&1["id"] == id))

      assert entry["name"] == "listed"
      assert entry["key_prefix"] == String.slice(secret, 0, 12)
      refute Map.has_key?(entry, "key")
      refute Map.has_key?(entry, "key_hash")
      refute Jason.encode!(body) =~ secret
    end

    test "shows a single key, and 404s for unknown or non-numeric ids", %{conn: conn} do
      {id, _} = create_key!(conn, "single")

      shown = conn |> get("#{@path}/#{id}") |> json_response(200)
      assert shown["data"]["name"] == "single"
      refute Map.has_key?(shown["data"], "key")

      assert json_response(get(conn, "#{@path}/0"), 404)
      assert json_response(get(conn, "#{@path}/abc"), 404)
    end
  end

  describe "PATCH /api-keys/:id" do
    test "renames a key without changing its secret", %{conn: conn} do
      {id, secret} = create_key!(conn, "before")

      resp = conn |> patch("#{@path}/#{id}", %{"name" => "after"}) |> json_response(200)
      assert resp["data"]["name"] == "after"

      assert ApiKey.get_by_secret(secret).id == id
    end

    test "rejects a blank or missing name and a name taken by another key", %{conn: conn} do
      {id, _} = create_key!(conn, "rename-me")
      create_key!(conn, "taken")

      assert json_response(patch(conn, "#{@path}/#{id}", %{"name" => ""}), 422)
      assert json_response(patch(conn, "#{@path}/#{id}", %{}), 422)

      resp = conn |> patch("#{@path}/#{id}", %{"name" => "taken"}) |> json_response(422)
      assert resp["details"]["name"] == ["has already been taken"]
    end

    test "404s for an unknown id", %{conn: conn} do
      assert json_response(patch(conn, "#{@path}/0", %{"name" => "x"}), 404)
    end
  end

  describe "POST /api-keys/:id/rotate" do
    test "issues a new secret and invalidates the old one", %{conn: conn} do
      {id, old_secret} = create_key!(conn, "rotating")

      resp = conn |> post("#{@path}/#{id}/rotate") |> json_response(200)
      new_secret = resp["data"]["key"]

      assert resp["message"] =~ "rotated"
      assert resp["data"]["id"] == id
      assert resp["data"]["name"] == "rotating"
      assert new_secret != old_secret

      assert ApiKey.get_by_secret(old_secret) == nil
      assert ApiKey.get_by_secret(new_secret).id == id
    end

    test "404s for an unknown id", %{conn: conn} do
      assert json_response(post(conn, "#{@path}/0/rotate"), 404)
    end
  end

  describe "DELETE /api-keys/:id" do
    test "deletes the key so it stops authenticating", %{conn: conn} do
      {id, secret} = create_key!(conn, "doomed")

      assert json_response(delete(conn, "#{@path}/#{id}"), 200)["success"] == true
      assert json_response(get(conn, "#{@path}/#{id}"), 404)
      assert ApiKey.get_by_secret(secret) == nil
    end

    test "404s for an unknown id", %{conn: conn} do
      assert json_response(delete(conn, "#{@path}/0"), 404)
    end
  end

  describe "issued keys on the public API (ReadAuthPlug)" do
    test "grant read-only access", %{conn: conn} do
      {_id, secret} = create_key!(conn, "reader")

      plugged =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("x-api-key", secret)
        |> ReadAuthPlug.call([])

      assert plugged.assigns.authenticated == true
      assert plugged.assigns.auth_level == :read_only

      assert json_response(get(with_key(conn, secret), "/stac/api/v1/collections"), 200)
    end

    test "unknown, rotated-away and deleted keys stay unauthenticated", %{conn: conn} do
      {id, old_secret} = create_key!(conn, "short-lived")
      conn |> post("#{@path}/#{id}/rotate") |> json_response(200)

      for secret <- ["stac_ro_not-a-real-key", old_secret] do
        plugged =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("x-api-key", secret)
          |> ReadAuthPlug.call([])

        assert plugged.assigns.authenticated == false
        assert plugged.assigns.auth_level == nil
      end
    end

    test "static keys keep working", %{conn: conn} do
      assert ReadAuthPlug.call(conn, []).assigns.auth_level == :read_write

      ro = Phoenix.ConnTest.build_conn() |> read_only_conn() |> ReadAuthPlug.call([])
      assert ro.assigns.auth_level == :read_only
    end
  end

  describe "last_used_at" do
    defp use_key(secret) do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-api-key", secret)
      |> ReadAuthPlug.call([])
    end

    test "is set on first use and shown in listings", %{conn: conn} do
      {id, secret} = create_key!(conn, "tracked")
      assert Repo.get!(ApiKey, id).last_used_at == nil

      use_key(secret)

      assert %DateTime{} = Repo.get!(ApiKey, id).last_used_at
      listed = conn |> get("#{@path}/#{id}") |> json_response(200)
      assert listed["data"]["last_used_at"] != nil
    end

    test "is not rewritten when it is recent, but is when it is over an hour old", %{conn: conn} do
      {id, secret} = create_key!(conn, "throttled")
      use_key(secret)
      first = Repo.get!(ApiKey, id).last_used_at

      use_key(secret)
      assert Repo.get!(ApiKey, id).last_used_at == first

      stale = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [last_used_at: stale])

      use_key(secret)
      assert DateTime.compare(Repo.get!(ApiKey, id).last_used_at, stale) == :gt
    end
  end

  describe "browse unlock" do
    test "an issued key unlocks the browser as read-only", %{conn: conn} do
      {_id, secret} = create_key!(conn, "browser-user")

      unlocked =
        Phoenix.ConnTest.build_conn()
        |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

      assert redirected_to(unlocked) =~ "/stac/web/browse"
      assert get_session(unlocked, :browse_authenticated) == true
      assert get_session(unlocked, :browse_auth_level) == :read_only
    end

    test "a deleted issued key no longer unlocks the browser", %{conn: conn} do
      {id, secret} = create_key!(conn, "browser-gone")
      conn |> delete("#{@path}/#{id}") |> json_response(200)

      locked =
        Phoenix.ConnTest.build_conn()
        |> post(~p"/stac/web/auth", %{"api_key" => secret, "return_to" => "/stac/web/browse"})

      assert get_session(locked, :browse_authenticated) != true
    end
  end
end
