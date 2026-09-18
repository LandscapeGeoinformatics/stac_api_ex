defmodule StacApiWeb.RootControllerDocsTest do
  use StacApiWeb.ConnCase, async: true

  alias StacApiWeb.ApiDocs

  test "docs page renders in the site layout with every read endpoint and hides the management API",
       %{conn: conn} do
    html = conn |> get("/stac/api/v1/docs") |> html_response(200)

    refute html =~ "Management API"
    refute html =~ "/stac/manage/"
    refute html =~ "RW key required"
    refute html =~ "read-write"
    # the same lock control as on the browse pages
    assert html =~ ~s(action="/stac/web/auth")
    assert html =~ ~s(value="/stac/api/v1/docs")

    # site layout (navbar) and the themed header
    assert html =~ "navbar bg-secondary"
    assert html =~ "Geokuup STAC API"
    assert html =~ "Getting started"
    assert html =~ "Authentication"
    assert html =~ "X-API-Key"
    assert html =~ "Conformance classes"

    for ep <- ApiDocs.endpoints() do
      assert html =~ ~s(id="#{ep.id}"), "missing endpoint card #{ep.id}"
      assert html =~ ep.path
    end

    # method colour coding and auth badges
    assert html =~ "bg-accent text-white"
    assert html =~ "Try it"
    # copyable curl examples
    assert html =~ ~s(id="search-get-curl")
    assert html =~ "curl -s"
  end

  test "docs page shows the management API only for a read-write session", %{conn: conn} do
    ro_html =
      conn
      |> Plug.Test.init_test_session(%{browse_authenticated: true, browse_auth_level: :read_only})
      |> get("/stac/api/v1/docs")
      |> html_response(200)

    refute ro_html =~ "/stac/manage/"
    assert ro_html =~ "Private: ON"

    rw_html =
      conn
      |> Plug.Test.init_test_session(%{
        browse_authenticated: true,
        browse_auth_level: :read_write
      })
      |> get("/stac/api/v1/docs")
      |> html_response(200)

    assert rw_html =~ "Management API"
    assert rw_html =~ "RW key required"
    assert rw_html =~ "bg-red-600 text-white"

    for ep <- ApiDocs.endpoints(include_management: true) do
      assert rw_html =~ ~s(id="#{ep.id}"), "missing endpoint card #{ep.id}"
    end
  end

  test "unlocking with the read-write key from the docs page returns there and reveals the management API",
       %{conn: conn} do
    rw_key = :stac_api |> Application.get_env(:api_keys) |> Map.get(:read_write) |> List.first()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/stac/web/auth", %{"api_key" => rw_key, "return_to" => "/stac/api/v1/docs"})

    assert redirected_to(conn) == "/stac/api/v1/docs"
    assert get_session(conn, :browse_auth_level) == :read_write

    html = conn |> recycle() |> get("/stac/api/v1/docs") |> html_response(200)
    assert html =~ "/stac/manage/v1/items/import"

    conn = conn |> recycle() |> post("/stac/web/logout", %{"return_to" => "/stac/api/v1/docs"})
    assert redirected_to(conn) == "/stac/api/v1/docs"
    assert get_session(conn, :browse_auth_level) == nil
  end

  test "a read-only key unlocks browsing but not the management docs", %{conn: conn} do
    ro_key = :stac_api |> Application.get_env(:api_keys) |> Map.get(:read_only) |> List.first()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/stac/web/auth", %{"api_key" => ro_key, "return_to" => "/stac/api/v1/docs"})

    assert get_session(conn, :browse_authenticated) == true
    assert get_session(conn, :browse_auth_level) == :read_only
  end

  test "openapi.json describes read access by default and the management API only with a RW key",
       %{conn: conn} do
    conn = get(conn, "/stac/api/v1/openapi.json")
    assert response_content_type(conn, :json) =~ "vnd.oai.openapi+json"
    spec = json_response(conn, 200)

    assert spec["openapi"] == "3.0.3"
    assert spec["info"]["title"] == "Geokuup STAC API"

    assert %{"ApiKeyAuth" => %{"in" => "header", "name" => "X-API-Key"}} =
             spec["components"]["securitySchemes"]

    refute Enum.any?(Map.keys(spec["paths"]), &String.starts_with?(&1, "/stac/manage/"))
    refute Jason.encode!(spec) =~ "Management API"
    refute Map.has_key?(spec["components"]["schemas"], "BulkImportResult")

    for ep <- ApiDocs.endpoints() do
      op = get_in(spec, ["paths", ep.path, String.downcase(ep.method)])
      assert op, "missing operation #{ep.method} #{ep.path}"
      assert op["operationId"] == ep.id
    end

    assert get_in(spec, ["paths", "/stac/api/v1/search", "get", "security"]) ==
             [%{}, %{"ApiKeyAuth" => []}]

    # read-only header: still the read-only view
    ro_spec =
      conn
      |> recycle()
      |> read_only_conn()
      |> get("/stac/api/v1/openapi.json")
      |> json_response(200)

    refute Map.has_key?(ro_spec["paths"], "/stac/manage/v1/items")

    # read-write header: full document
    spec =
      conn
      |> recycle()
      |> authenticated_conn()
      |> get("/stac/api/v1/openapi.json")
      |> json_response(200)

    for ep <- ApiDocs.endpoints(include_management: true) do
      op = get_in(spec, ["paths", ep.path, String.downcase(ep.method)])
      assert op, "missing operation #{ep.method} #{ep.path}"
      assert Map.has_key?(op["responses"], "200") or Map.has_key?(op["responses"], "201")
    end

    assert get_in(spec, ["paths", "/stac/manage/v1/items", "post", "security"]) ==
             [%{"ApiKeyAuth" => []}]

    # every $ref resolves in the full document
    refs =
      spec
      |> Jason.encode!()
      |> then(&Regex.scan(~r{"#/components/schemas/(\w+)"}, &1))
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    for name <- refs do
      assert Map.has_key?(spec["components"]["schemas"], name), "unresolved schema #{name}"
    end

    # read-write browser session: full document too (the openapi.json button on the docs page)
    session_spec =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(%{
        browse_authenticated: true,
        browse_auth_level: :read_write
      })
      |> get("/stac/api/v1/openapi.json")
      |> json_response(200)

    assert Map.has_key?(session_spec["paths"], "/stac/manage/v1/items/import")
  end

  test "conformance endpoint and landing page agree with the docs", %{conn: conn} do
    conformance = conn |> get("/stac/api/v1/conformance") |> json_response(200)
    landing = conn |> get("/stac/api/v1/") |> json_response(200)

    assert conformance["conformsTo"] == ApiDocs.conformance_classes()
    assert landing["conformsTo"] == ApiDocs.conformance_classes()
  end

  test "curl examples fill path params and carry the key only for RW endpoints" do
    item = ApiDocs.find_endpoint("collection-item")

    assert ApiDocs.example_path(item) ==
             "/stac/api/v1/collections/estonia-topo-10m/items/dem_10m_clipped"

    refute ApiDocs.curl_example(item, "https://x") =~ "X-API-Key"

    create = ApiDocs.find_endpoint("manage-items-create")
    curl = ApiDocs.curl_example(create, "https://x")
    assert curl =~ "-X POST"
    assert curl =~ "X-API-Key: $STAC_API_KEY"
    assert curl =~ "Content-Type: application/json"
    assert curl =~ ~s("https://x/stac/manage/v1/items")
    assert ApiDocs.try_href(create) == nil
    assert ApiDocs.try_href(ApiDocs.find_endpoint("manage-catalogs-list")) == nil
    assert ApiDocs.try_href(item) =~ "/items/dem_10m_clipped"
  end
end
