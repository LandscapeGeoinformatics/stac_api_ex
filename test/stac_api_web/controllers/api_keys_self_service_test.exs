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

  # Moves the key's expiry into the past; the API itself refuses to create that.
  defp expire!(id) do
    past = DateTime.add(DateTime.utc_now(), -60, :second)
    Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [expires_at: past])
  end

  # Pretends the current secret was issued `seconds` ago.
  defp issued_ago!(id, seconds) do
    at = DateTime.add(DateTime.utc_now(), -seconds, :second)
    Repo.update_all(from(k in ApiKey, where: k.id == ^id), set: [rotated_at: at])
  end

  describe "rotated_at and rotated_by" do
    test "a new key gets rotated_at from the app clock, not from the database default" do
      {_raw, secret_attrs} = ApiKey.generate_secret("read_only")
      before = DateTime.utc_now()

      changeset = ApiKey.changeset(%ApiKey{}, Map.put(secret_attrs, :name, "clock"))
      rotated_at = Ecto.Changeset.get_change(changeset, :rotated_at)

      assert %DateTime{} = rotated_at
      assert DateTime.compare(rotated_at, before) != :lt
      assert DateTime.compare(rotated_at, DateTime.utc_now()) != :gt
    end

    test "editing or loading an existing key does not touch rotated_at", %{conn: conn} do
      {id, _} = create_key!(conn, "unchanged-clock")
      loaded = Repo.get!(ApiKey, id)

      changeset = ApiKey.update_changeset(loaded, %{"note" => "x"})
      refute Map.has_key?(changeset.changes, :rotated_at)

      changeset = ApiKey.changeset(loaded, %{name: "renamed"})
      refute Map.has_key?(changeset.changes, :rotated_at)
    end

    test "rotating right after creating never lands before the creation", %{conn: conn} do
      for n <- 1..5 do
        {id, secret} = create_key!(conn, "quick-#{n}")
        created_at = Repo.get!(ApiKey, id).rotated_at

        secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)

        assert DateTime.compare(Repo.get!(ApiKey, id).rotated_at, created_at) != :lt
      end
    end

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

  describe "GET /key" do
    test "returns the key's own data, without secret, hash, contact or note", %{conn: conn} do
      {id, secret} =
        create_key!(conn, "mine", %{
          "role" => "read_write",
          "expires_at" => future(),
          "contact" => "owner@example.org",
          "note" => "admin metadata"
        })

      resp = secret |> with_key() |> get("#{@public}/key") |> json_response(200)

      assert Map.keys(resp["data"]) |> Enum.sort() ==
               ~w(expires_at key_prefix last_used_at name role rotated_at secret_expires_at)

      assert resp["data"]["name"] == "mine"
      assert resp["data"]["role"] == "read_write"
      assert resp["data"]["key_prefix"] == String.slice(secret, 0, 12)
      assert resp["data"]["secret_expires_at"] == resp["data"]["expires_at"]
      refute inspect(resp) =~ secret
      refute inspect(resp) =~ Repo.get!(ApiKey, id).key_hash
    end

    test "works for a read-only key too", %{conn: conn} do
      {_id, secret} = create_key!(conn, "reader")

      resp = secret |> with_key() |> get("#{@public}/key") |> json_response(200)
      assert resp["data"]["role"] == "read_only"
      assert resp["data"]["expires_at"] == nil
      assert resp["data"]["secret_expires_at"] == nil
    end

    test "secret_expires_at follows the max-age when it ends first", %{conn: conn} do
      previous = Application.get_env(:stac_api, :api_key_max_age_days)
      on_exit(fn -> Application.put_env(:stac_api, :api_key_max_age_days, previous) end)
      Application.put_env(:stac_api, :api_key_max_age_days, 5)

      {id, secret} = create_key!(conn, "ages", %{"expires_at" => future(30 * 86_400)})

      resp = secret |> with_key() |> get("#{@public}/key") |> json_response(200)
      expected = DateTime.add(Repo.get!(ApiKey, id).rotated_at, 5 * 86_400, :second)

      assert {:ok, returned, 0} = DateTime.from_iso8601(resp["data"]["secret_expires_at"])
      assert DateTime.compare(returned, expected) == :eq
    end
  end

  describe "POST /key/rotate" do
    test "returns a new secret once and rejects the old one right away", %{conn: conn} do
      {id, old_secret} = create_key!(conn, "self-rotating", %{"role" => "read_write"})
      before = Repo.get!(ApiKey, id)

      resp = old_secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)
      new_secret = resp["data"]["key"]

      assert "stac_rw_" <> _ = new_secret
      assert new_secret != old_secret
      assert resp["data"]["key_prefix"] == String.slice(new_secret, 0, 12)
      assert json_response(get(with_key(old_secret), "#{@public}/key"), 401)
      assert json_response(get(with_key(new_secret), "#{@public}/key"), 200)

      # The secret is shown once: later reads do not contain it.
      again = new_secret |> with_key() |> get("#{@public}/key") |> json_response(200)
      refute Map.has_key?(again["data"], "key")

      after_rotate = Repo.get!(ApiKey, id)
      assert after_rotate.rotated_by == "self"
      assert after_rotate.key_prefix != before.key_prefix
      assert DateTime.compare(after_rotate.rotated_at, before.rotated_at) != :lt
    end

    test "changes nothing but the secret, the prefix and the rotation info", %{conn: conn} do
      {id, secret} =
        create_key!(conn, "unchanged", %{
          "role" => "read_write",
          "expires_at" => future(),
          "contact" => "owner@example.org",
          "note" => "stays"
        })

      before = Repo.get!(ApiKey, id)
      secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)
      after_rotate = Repo.get!(ApiKey, id)

      assert after_rotate.role == before.role
      assert after_rotate.name == before.name
      assert after_rotate.contact == before.contact
      assert after_rotate.note == before.note
      assert DateTime.compare(after_rotate.expires_at, before.expires_at) == :eq
    end

    test "works for a read-only key and keeps its prefix kind", %{conn: conn} do
      {_id, secret} = create_key!(conn, "ro-rotating")

      resp = secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)
      assert "stac_ro_" <> _ = resp["data"]["key"]
      assert resp["data"]["role"] == "read_only"
    end

    test "a self-rotation is visible in the admin listing", %{conn: conn} do
      {id, secret} = create_key!(conn, "visible")
      secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)

      shown = conn |> get("#{@path}/#{id}") |> json_response(200)
      assert shown["data"]["rotated_by"] == "self"
    end

    test "a rotated key still stops working at expires_at", %{conn: conn} do
      {id, secret} = create_key!(conn, "final-date", %{"expires_at" => future()})

      new_secret =
        secret
        |> with_key()
        |> post("#{@public}/key/rotate")
        |> json_response(200)
        |> get_in(["data", "key"])

      expire!(id)

      assert json_response(get(with_key(new_secret), "#{@public}/key"), 401)
    end

    test "a second self-rotation within an hour gets 429 with Retry-After", %{conn: conn} do
      {id, secret} = create_key!(conn, "twice")

      first = secret |> with_key() |> post("#{@public}/key/rotate")
      new_secret = json_response(first, 200)["data"]["key"]

      second = new_secret |> with_key() |> post("#{@public}/key/rotate")
      assert json_response(second, 429)
      assert [retry_after] = get_resp_header(second, "retry-after")
      assert String.to_integer(retry_after) in 1..3600

      # The refused rotation changed nothing: the secret still works.
      assert json_response(get(with_key(new_secret), "#{@public}/key"), 200)

      # An hour later it is allowed again.
      issued_ago!(id, 3601)
      assert json_response(post(with_key(new_secret), "#{@public}/key/rotate"), 200)
    end

    test "an admin rotation does not count towards the self-rotation limit", %{conn: conn} do
      {id, secret} = create_key!(conn, "admin-then-self")
      secret |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)

      admin_secret =
        conn |> post("#{@path}/#{id}/rotate") |> json_response(200) |> get_in(["data", "key"])

      assert json_response(post(with_key(admin_secret), "#{@public}/key/rotate"), 200)
    end

    test "a key that is past max-age cannot rotate itself, the admin rotate revives it",
         %{conn: conn} do
      previous = Application.get_env(:stac_api, :api_key_max_age_days)
      on_exit(fn -> Application.put_env(:stac_api, :api_key_max_age_days, previous) end)
      Application.put_env(:stac_api, :api_key_max_age_days, 30)

      {id, secret} = create_key!(conn, "too-late-to-renew")
      issued_ago!(id, 31 * 86_400)

      assert json_response(post(with_key(secret), "#{@public}/key/rotate"), 401)

      revived =
        conn |> post("#{@path}/#{id}/rotate") |> json_response(200) |> get_in(["data", "key"])

      assert json_response(get(with_key(revived), "#{@public}/key"), 200)
    end

    test "a stale struct cannot rotate again (concurrent rotation)", %{conn: conn} do
      {id, _secret} = create_key!(conn, "racing")
      loaded = Repo.get!(ApiKey, id)

      assert {:ok, _, _} = ApiKey.rotate_secret_by_owner(loaded)
      assert {:error, :stale} = ApiKey.rotate_secret_by_owner(loaded)
    end
  end

  describe "who may use /key" do
    test "no key, an invalid key or an expired key get 401", %{conn: conn} do
      {id, secret} = create_key!(conn, "soon-gone", %{"expires_at" => future()})
      expire!(id)

      for {label, c} <- [
            {"no key", Phoenix.ConnTest.build_conn()},
            {"invalid", with_key("stac_ro_not-a-real-key")},
            {"expired", with_key(secret)}
          ] do
        assert json_response(get(c, "#{@public}/key"), 401), "GET with #{label}"
        assert json_response(post(c, "#{@public}/key/rotate"), 401), "POST with #{label}"
      end
    end

    test "the static env keys get 404, never a 500" do
      %{read_write: [rw | _], read_only: [ro | _]} = Application.fetch_env!(:stac_api, :api_keys)

      for key <- [rw, ro] do
        assert json_response(get(with_key(key), "#{@public}/key"), 404)
        assert json_response(post(with_key(key), "#{@public}/key/rotate"), 404)
      end
    end

    test "a key only ever sees and rotates itself", %{conn: conn} do
      {other_id, other_secret} = create_key!(conn, "someone-else")
      {_id, mine} = create_key!(conn, "me")

      mine |> with_key() |> post("#{@public}/key/rotate") |> json_response(200)

      # The other key is untouched and still works with its old secret.
      assert Repo.get!(ApiKey, other_id).rotated_by == nil
      assert json_response(get(with_key(other_secret), "#{@public}/key"), 200)
    end
  end

  describe "documentation" do
    test "the public docs and the OpenAPI document list /key and /key/rotate" do
      html = Phoenix.ConnTest.build_conn() |> get("#{@public}/docs") |> html_response(200)
      assert html =~ "/stac/api/v1/key/rotate"
      assert html =~ "Personal key required"

      openapi =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("accept", "application/json")
        |> get("#{@public}/openapi.json")
        |> json_response(200)

      assert get_in(openapi, ["paths", "/stac/api/v1/key", "get"])
      assert get_in(openapi, ["paths", "/stac/api/v1/key/rotate", "post"])
      assert get_in(openapi, ["components", "schemas", "OwnKey"])
    end

    test "the docs page keeps three columns for the three getting-started cards" do
      html = Phoenix.ConnTest.build_conn() |> get("#{@public}/docs") |> html_response(200)

      # Getting started has three cards in a 3-column grid; only the (wider)
      # authentication grid uses two columns.
      assert html =~ ~s(grid grid-cols-1 md:grid-cols-3 gap-3 text-sm)
      assert html =~ ~s(grid grid-cols-1 md:grid-cols-2 gap-3 text-sm)
      refute html =~ "two levels"
      assert html =~ "badge that shows which key it needs"
    end

    test "the api-keys endpoints are :admin in the docs, the data endpoints stay :rw" do
      management =
        StacApiWeb.ApiDocs.groups(include_management: true)
        |> Enum.find(&(&1.id == "management-api"))

      {keys, others} =
        Enum.split_with(management.endpoints, &String.starts_with?(&1.id, "manage-api-keys-"))

      assert length(keys) == 6
      assert Enum.all?(keys, &(&1.auth == :admin))
      assert Enum.all?(others, &(&1.auth == :rw))

      assert {"Static RW key only", _, hint} = StacApiWeb.RootHTML.auth_badge(:admin)
      assert hint =~ "even read-write ones"
    end

    test "the api-keys operations in the OpenAPI document still require the API key", %{
      conn: conn
    } do
      openapi = conn |> get("#{@public}/openapi.json") |> json_response(200)

      for {path, method} <- [
            {"/stac/manage/v1/api-keys", "get"},
            {"/stac/manage/v1/api-keys/{id}/rotate", "post"}
          ] do
        assert get_in(openapi, ["paths", path, method, "security"]) == [%{"ApiKeyAuth" => []}]
      end
    end

    test "the management docs describe rotated_at and rotated_by", %{conn: conn} do
      openapi = conn |> get("#{@public}/openapi.json") |> json_response(200)
      props = get_in(openapi, ["components", "schemas", "ApiKey", "properties"])

      assert props["rotated_at"]
      assert props["rotated_by"]["enum"] == ["admin", "self"]
    end
  end
end
