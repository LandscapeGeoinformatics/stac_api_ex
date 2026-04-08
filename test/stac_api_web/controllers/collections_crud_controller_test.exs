defmodule StacApiWeb.CollectionsCrudControllerTest do
  use StacApiWeb.ConnCase, async: true
  alias StacApi.Data.{Collection, Catalog, Item}
  alias StacApi.Repo

  defp add_auth_header(conn, api_key) do
    put_req_header(conn, "x-api-key", api_key)
  end

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)
    catalog_params = %{
      "id" => "test-catalog",
      "title" => "Test Catalog",
      "description" => "Test"
    }
    post(auth_conn, ~p"/stac/manage/v1/catalogs", catalog_params)

    {:ok, conn: auth_conn, api_key: "test-api-key-2024"}
  end

  describe "POST /collections - create collection" do
    test "creates a root collection (without catalog)", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "root-collection",
        "title" => "Root Collection",
        "description" => "A root-level collection",
        "license" => "CC-BY-4.0",
        "stac_version" => "1.0.0",
        "extent" => %{
          "spatial" => %{"bbox" => [[-180, -90, 180, 90]]},
          "temporal" => %{"interval" => [["2020-01-01T00:00:00Z", "2024-12-31T23:59:59Z"]]}
        }
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      assert response = json_response(conn, 201)
      assert response["success"] == true
      assert response["data"]["id"] == "root-collection"
      assert response["data"]["title"] == "Root Collection"
      assert response["data"]["type"] == "Collection"
      assert response["data"]["license"] == "CC-BY-4.0"
    end

    test "creates a collection under a catalog", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "catalog-collection",
        "title" => "Collection in Catalog",
        "description" => "Collection under test-catalog",
        "license" => "CC-BY-4.0",
        "catalog_id" => "test-catalog",
        "stac_version" => "1.0.0",
        "extent" => %{
          "spatial" => %{"bbox" => [[-180, -90, 180, 90]]},
          "temporal" => %{"interval" => [["2020-01-01T00:00:00Z", nil]]}
        }
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      assert response = json_response(conn, 201)
      assert response["data"]["id"] == "catalog-collection"
    end

    test "returns 409 when collection ID already exists", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "duplicate-collection",
        "title" => "Duplicate",
        "description" => "Test",
        "license" => "CC-BY-4.0"
      }

      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)
      assert response = json_response(conn, 409)
      assert response["error"] =~ "already exists"
    end

    test "returns 400 when missing required field (id)", %{conn: conn, api_key: api_key} do
      params = %{
        "title" => "No ID",
        "description" => "Missing ID",
        "license" => "CC-BY-4.0"
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "id"
    end

    test "returns 400 when catalog_id does not exist", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "invalid-catalog-collection",
        "title" => "Invalid Catalog",
        "description" => "Bad catalog",
        "license" => "CC-BY-4.0",
        "catalog_id" => "non-existent-catalog"
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "catalog"
    end
  end

  describe "GET /collections - list all collections" do
    test "returns empty list when no collections exist", %{conn: conn} do
      conn = get(conn, ~p"/stac/manage/v1/collections")
      assert response = json_response(conn, 200)
      assert response["collections"] == []
      assert is_list(response["links"])
    end

    test "returns all collections", %{conn: conn, api_key: api_key} do
      col1_params = %{
        "id" => "col-1",
        "title" => "Collection 1",
        "description" => "First",
        "license" => "CC-BY-4.0"
      }
      col2_params = %{
        "id" => "col-2",
        "title" => "Collection 2",
        "description" => "Second",
        "license" => "CC-BY-4.0"
      }

      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", col1_params)
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", col2_params)

      conn = get(conn, ~p"/stac/manage/v1/collections")
      assert response = json_response(conn, 200)
      assert length(response["collections"]) == 2

      ids = Enum.map(response["collections"], & &1["id"])
      assert "col-1" in ids
      assert "col-2" in ids
    end
  end

  describe "GET /collections/:id - show specific collection" do
    test "returns a specific collection", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "show-collection",
        "title" => "Show Test",
        "description" => "Test",
        "license" => "CC-BY-4.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      conn = get(conn, ~p"/stac/manage/v1/collections/show-collection")
      assert response = json_response(conn, 200)
      assert response["id"] == "show-collection"
      assert response["title"] == "Show Test"
      assert response["type"] == "Collection"
    end

    test "returns 404 for non-existent collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/manage/v1/collections/non-existent")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "PUT /collections/:id - update collection" do
    test "fully replaces a collection", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "update-collection",
        "title" => "Original Title",
        "description" => "Original",
        "license" => "CC-BY-4.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      update_params = %{
        "id" => "update-collection",
        "title" => "Updated Title",
        "description" => "Updated",
        "license" => "CC0-1.0"
      }

      conn = conn |> add_auth_header(api_key) |> put(~p"/stac/manage/v1/collections/update-collection", update_params)
      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["data"]["title"] == "Updated Title"
      assert response["data"]["license"] == "CC0-1.0"
    end

    test "returns 404 when updating non-existent collection", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "non-existent",
        "title" => "Title",
        "license" => "CC-BY-4.0"
      }

      conn = conn |> add_auth_header(api_key) |> put(~p"/stac/manage/v1/collections/non-existent", params)
      assert response = json_response(conn, 404)
    end
  end

  describe "PATCH /collections/:id - partial update collection" do
    test "partially updates a collection", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "patch-collection",
        "title" => "Original Title",
        "description" => "Original",
        "license" => "CC-BY-4.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      patch_params = %{
        "id" => "patch-collection",
        "title" => "Patched Title"
      }

      conn = conn |> add_auth_header(api_key) |> patch(~p"/stac/manage/v1/collections/patch-collection", patch_params)
      assert response = json_response(conn, 200)
      assert response["data"]["title"] == "Patched Title"
      assert response["data"]["description"] == "Original"
    end

    test "returns 404 when patching non-existent collection", %{conn: conn, api_key: api_key} do
      params = %{"id" => "non-existent", "title" => "Title"}

      conn = conn |> add_auth_header(api_key) |> patch(~p"/stac/manage/v1/collections/non-existent", params)
      assert response = json_response(conn, 404)
    end
  end

  describe "DELETE /collections/:id - delete collection" do
    test "deletes a collection successfully", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "delete-collection",
        "title" => "To Delete",
        "license" => "CC-BY-4.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", params)

      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/collections/delete-collection")
      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "deleted successfully"

      # Verify it's gone
      get_conn = get(authenticated_conn(build_conn()), ~p"/stac/manage/v1/collections/delete-collection")
      assert json_response(get_conn, 404)
    end

    test "cascade deletes items in collection", %{conn: conn, api_key: api_key} do
      # Create a collection
      col_params = %{
        "id" => "col-with-items",
        "title" => "Collection with Items",
        "license" => "CC-BY-4.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/collections", col_params)

      # Create items in the collection
      item_params = %{
        "id" => "test-item",
        "collection_id" => "col-with-items",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "Test item"}
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/items", item_params)

      # Delete the collection
      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/collections/col-with-items")
      assert response = json_response(conn, 200)
      assert response["cascade_deleted"]["items"] >= 1

      # Verify item is gone
      get_conn = get(authenticated_conn(build_conn()), ~p"/stac/manage/v1/items/test-item")
      assert json_response(get_conn, 404)
    end

    test "returns 404 when deleting non-existent collection", %{conn: conn, api_key: api_key} do
      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/collections/non-existent")
      assert response = json_response(conn, 404)
    end
  end
end
