defmodule StacApiWeb.CatalogsCrudControllerTest do
  use StacApiWeb.ConnCase, async: true
  alias StacApi.Data.Catalog
  alias StacApi.Repo

  setup %{conn: conn} do
    {:ok, conn: authenticated_conn(conn), api_key: "test-api-key-2024"}
  end

  defp add_auth_header(conn, api_key) do
    put_req_header(conn, "x-api-key", api_key)
  end

  describe "POST /catalogs - create catalog" do
    test "creates a root catalog successfully", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "test-catalog",
        "title" => "Test Catalog",
        "description" => "A test catalog",
        "type" => "Catalog",
        "stac_version" => "1.0.0"
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      assert response = json_response(conn, 201)
      assert response["success"] == true
      assert response["message"] == "Catalog created successfully"
      assert response["data"]["id"] == "test-catalog"
      assert response["data"]["title"] == "Test Catalog"
      assert response["data"]["type"] == "Catalog"
    end

    test "creates a nested catalog successfully", %{conn: conn, api_key: api_key} do
      # Create parent catalog first
      parent_params = %{
        "id" => "parent-catalog",
        "title" => "Parent Catalog",
        "description" => "Parent",
        "type" => "Catalog",
        "stac_version" => "1.0.0"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", parent_params)

      # Create nested catalog
      nested_params = %{
        "id" => "nested-catalog",
        "title" => "Nested Catalog",
        "description" => "Nested under parent",
        "type" => "Catalog",
        "stac_version" => "1.0.0",
        "parent_catalog_id" => "parent-catalog"
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", nested_params)
      assert response = json_response(conn, 201)
      assert response["data"]["id"] == "nested-catalog"
    end

    test "returns 409 conflict when catalog ID already exists", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "duplicate-catalog",
        "title" => "Duplicate",
        "description" => "Test",
        "type" => "Catalog",
        "stac_version" => "1.0.0"
      }

      # Create first time
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      # Try to create again
      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)
      assert response = json_response(conn, 409)
      assert response["error"] =~ "already exists"
    end

    test "returns 400 for missing required field (id)", %{conn: conn, api_key: api_key} do
      params = %{
        "title" => "No ID Catalog",
        "description" => "Missing ID",
        "type" => "Catalog"
      }

      conn = conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "id"
    end
  end

  describe "GET /catalogs - list all catalogs" do
    test "returns a list of catalogs", %{conn: conn} do
      conn = get(conn, ~p"/stac/manage/v1/catalogs")
      assert response = json_response(conn, 200)
      assert is_list(response["catalogs"])
      assert is_list(response["links"])
    end

    test "returns all catalogs", %{conn: conn, api_key: api_key} do
      # Create two catalogs with unique IDs
      unique_id1 = "cat-#{:rand.uniform(10000)}-1"
      unique_id2 = "cat-#{:rand.uniform(10000)}-2"

      cat1_params = %{"id" => unique_id1, "title" => "Catalog 1", "description" => "First"}
      cat2_params = %{"id" => unique_id2, "title" => "Catalog 2", "description" => "Second"}

      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", cat1_params)
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", cat2_params)

      conn = get(conn, ~p"/stac/manage/v1/catalogs")
      assert response = json_response(conn, 200)
      assert is_list(response["catalogs"])
      assert length(response["catalogs"]) >= 2

      ids = Enum.map(response["catalogs"], & &1["id"])
      assert unique_id1 in ids
      assert unique_id2 in ids
    end
  end

  describe "GET /catalogs/:id - show specific catalog" do
    test "returns a specific catalog", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "show-catalog",
        "title" => "Show Test",
        "description" => "Test"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      conn = get(conn, ~p"/stac/manage/v1/catalogs/show-catalog")
      assert response = json_response(conn, 200)
      assert response["id"] == "show-catalog"
      assert response["title"] == "Show Test"
      assert response["type"] == "Catalog"
    end

    test "returns 404 for non-existent catalog", %{conn: conn} do
      conn = get(conn, ~p"/stac/manage/v1/catalogs/non-existent")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "PUT /catalogs/:id - update catalog" do
    test "fully replaces a catalog", %{conn: conn, api_key: api_key} do
      # Create a catalog first
      params = %{
        "id" => "update-catalog",
        "title" => "Original Title",
        "description" => "Original Description"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      # Update it
      update_params = %{
        "id" => "update-catalog",
        "title" => "Updated Title",
        "description" => "Updated Description"
      }

      conn = conn |> add_auth_header(api_key) |> put(~p"/stac/manage/v1/catalogs/update-catalog", update_params)
      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["data"]["title"] == "Updated Title"
    end

    test "returns 404 when updating non-existent catalog", %{conn: conn, api_key: api_key} do
      params = %{
        "id" => "non-existent",
        "title" => "Title"
      }

      conn = conn |> add_auth_header(api_key) |> put(~p"/stac/manage/v1/catalogs/non-existent", params)
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "PATCH /catalogs/:id - partial update catalog" do
    test "partially updates a catalog", %{conn: conn, api_key: api_key} do
      # Create a catalog
      params = %{
        "id" => "patch-catalog",
        "title" => "Original Title",
        "description" => "Original Description"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      # Partial update - only change title
      patch_params = %{
        "id" => "patch-catalog",
        "title" => "Patched Title"
      }

      conn = conn |> add_auth_header(api_key) |> patch(~p"/stac/manage/v1/catalogs/patch-catalog", patch_params)
      assert response = json_response(conn, 200)
      assert response["data"]["title"] == "Patched Title"
      assert response["data"]["description"] == "Original Description"
    end

    test "returns 404 when patching non-existent catalog", %{conn: conn, api_key: api_key} do
      params = %{"id" => "non-existent", "title" => "Title"}

      conn = conn |> add_auth_header(api_key) |> patch(~p"/stac/manage/v1/catalogs/non-existent", params)
      assert response = json_response(conn, 404)
    end
  end

  describe "DELETE /catalogs/:id - delete catalog" do
    test "deletes a catalog successfully", %{conn: conn, api_key: api_key} do
      # Create a catalog
      params = %{
        "id" => "delete-catalog",
        "title" => "To Delete"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", params)

      # Delete it
      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/catalogs/delete-catalog")
      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "deleted successfully"

      # Verify it's gone
      get_conn = get(authenticated_conn(build_conn()), ~p"/stac/manage/v1/catalogs/delete-catalog")
      assert json_response(get_conn, 404)
    end

    test "cascade deletes child catalogs and collections", %{conn: conn, api_key: api_key} do
      # Create parent catalog
      parent_params = %{
        "id" => "parent-delete",
        "title" => "Parent"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", parent_params)

      # Create child catalog
      child_params = %{
        "id" => "child-delete",
        "title" => "Child",
        "parent_catalog_id" => "parent-delete"
      }
      conn |> add_auth_header(api_key) |> post(~p"/stac/manage/v1/catalogs", child_params)

      # Delete parent - should cascade
      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/catalogs/parent-delete")
      assert response = json_response(conn, 200)
      assert response["cascade_deleted"]["catalogs"] >= 1

      # Verify child is gone
      get_conn = get(authenticated_conn(build_conn()), ~p"/stac/manage/v1/catalogs/child-delete")
      assert json_response(get_conn, 404)
    end

    test "returns 404 when deleting non-existent catalog", %{conn: conn, api_key: api_key} do
      conn = conn |> add_auth_header(api_key) |> delete(~p"/stac/manage/v1/catalogs/non-existent")
      assert response = json_response(conn, 404)
    end
  end
end
