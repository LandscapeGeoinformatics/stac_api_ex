defmodule StacApiWeb.StacBrowserControllerTest do
  use StacApiWeb.ConnCase, async: false

  alias StacApi.Data.{Catalog, Collection, Item, ItemAsset}

  test "browse page shows a visible unlock form for anonymous users", %{conn: conn} do
    conn = get(conn, ~p"/stac/web/browse")
    html = html_response(conn, 200)

    assert html =~ "API Key"
    assert html =~ ~s(action="/stac/web/auth")
    assert html =~ ~s(name="api_key")
    assert html =~ "Unlock"
  end

  test "posting a valid read-only key stores browse session auth", %{conn: conn} do
    read_only_key = configured_read_only_key()

    assert is_binary(read_only_key)

    conn =
      post(conn, ~p"/stac/web/auth", %{
        "api_key" => read_only_key,
        "return_to" => "/stac/web/browse"
      })

    assert redirected_to(conn) =~ "/stac/web/browse"
    assert get_session(conn, :browse_authenticated) == true
  end

  test "invalid read-only key does not unlock browse session", %{conn: conn} do
    conn =
      post(conn, ~p"/stac/web/auth", %{
        "api_key" => "wrong-key",
        "return_to" => "/stac/web/browse"
      })

    assert redirected_to(conn) =~ "/stac/web/browse"
    assert get_session(conn, :browse_authenticated) != true
  end

  test "absolute URL in return_to is rejected and redirects to browse", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/stac/web/auth", %{
        "api_key" => configured_read_only_key(),
        "return_to" => "https://evil.example"
      })

    assert redirected_to(conn) == "/stac/web/browse"
  end

  test "protocol-relative URL in return_to is rejected", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/stac/web/auth", %{
        "api_key" => configured_read_only_key(),
        "return_to" => "//evil.example"
      })

    assert redirected_to(conn) == "/stac/web/browse"
  end

  test "backslash host bypass in return_to is rejected", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/stac/web/auth", %{
        "api_key" => configured_read_only_key(),
        "return_to" => "/\\evil.example"
      })

    assert redirected_to(conn) == "/stac/web/browse"
  end

  test "private catalog is hidden from unauthenticated browse and visible after unlock", %{
    conn: conn
  } do
    catalog =
      %Catalog{}
      |> Catalog.changeset(%{
        id: "private-browser-catalog",
        title: "Private Browser Catalog",
        private: true,
        depth: 0
      })
      |> Repo.insert!()

    unauth_conn = get(conn, ~p"/stac/web/browse")
    unauth_html = html_response(unauth_conn, 200)
    refute unauth_html =~ catalog.title

    auth_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> put_session(:browse_authenticated, true)
      |> get(~p"/stac/web/browse")

    auth_html = html_response(auth_conn, 200)
    assert auth_html =~ catalog.title
  end

  describe "collection and item rendering" do
    setup do
      collection = insert_collection!("render-test-collection")

      insert_item!(collection, "render-raster-single",
        start: ~U[2021-11-26 00:00:00Z],
        end: ~U[2025-12-31 23:59:59Z],
        properties: %{
          "proj:code" => "EPSG:3301",
          "proj:shape" => [24576, 36864],
          "proj:transform" => [369_032.103, 10.0, 0.0, 6_622_901.06, 0.0, -10.0],
          "proj:bbox" => [369_032.1, 6_377_141.06, 737_672.1, 6_622_901.06],
          "proj:geometry" => %{"type" => "Polygon", "coordinates" => []},
          "custom:flag" => true
        },
        assets: %{"data" => cog_asset("potents_erosioon", ["data"])}
      )

      insert_item!(collection, "render-raster-multi",
        start: ~U[2019-04-01 00:00:00Z],
        end: ~U[2019-05-31 23:59:59Z],
        properties: %{"proj:code" => "EPSG:3301"},
        assets: %{
          "ndvi_max" => cog_asset("ndvi_max", ["data", "statistics"]),
          "ndvi_median" => cog_asset("ndvi_median", ["data"]),
          "ndvi_std" => cog_asset("ndvi_std", ["metadata", "statistics"])
        }
      )

      insert_item!(collection, "render-vector",
        start: ~U[2017-01-01 00:00:00Z],
        end: ~U[2017-12-31 23:59:59Z],
        properties: %{
          "proj:code" => "EPSG:3301",
          "lgeo:driver" => "FlatGeobuf",
          "table:row_count" => 4_496_422,
          "table:primary_geometry" => "geometry",
          "vector:geometry_types" => ["MultiLineString"],
          "table:columns" => [
            %{"name" => "cat", "type" => "int32"},
            %{"name" => "wrb_code", "type" => "string"},
            %{
              "name" => "geometry",
              "type" => "geometry",
              "vector:geometry_types" => ["MultiLineString"]
            }
          ]
        },
        assets: %{
          "data" => %{
            "href" => "https://example.org/ditches.fgb",
            "type" => "application/vnd.flatgeobuf",
            "roles" => ["data"],
            "file:size" => 642_908_696,
            "alternate" => %{
              "gpkg" => %{
                "href" => "https://example.org/ditches.gpkg",
                "type" => "application/geopackage+sqlite3"
              },
              "s3" => %{
                "href" => "s3://bucket/ditches.fgb",
                "type" => "application/vnd.flatgeobuf"
              }
            }
          }
        }
      )

      insert_item!(collection, "render-minimal", properties: %{}, assets: %{}, bbox: nil)

      {:ok, collection: collection}
    end

    test "single raster item renders temporal range, projection, bands and copyable hrefs", %{
      conn: conn
    } do
      html =
        conn
        |> get("/stac/web/browse/collection/render-test-collection/item/render-raster-single")
        |> html_response(200)

      assert html =~ "2021-11-26"
      assert html =~ "2025-12-31"
      assert html =~ "https://epsg.io/3301"
      assert html =~ "24,576 rows × 36,864 cols"
      assert html =~ "Raster bands"
      assert html =~ "float32"
      assert html =~ "s3://bucket/potents_erosioon.tif"
      assert html =~ ~s(data-copy="s3://bucket/potents_erosioon.tif")
      assert html =~ "COG GeoTIFF"
      assert html =~ "Raster · 1 asset"
      # proj:* keys are handled by the projection card, not the generic list
      refute html =~ "proj:transform</dt>"
      # unknown extension keys still show up, grouped by prefix
      assert html =~ "Custom"
      assert html =~ "Footprint in native CRS"
    end

    test "multi-asset item splits data from statistics", %{conn: conn} do
      html =
        conn
        |> get("/stac/web/browse/collection/render-test-collection/item/render-raster-multi")
        |> html_response(200)

      assert html =~ "Raster statistics · 3 assets"
      assert html =~ "Statistics &amp; metadata"
      assert html =~ "ndvi_std"
      assert index_of(html, "ndvi_median") < index_of(html, "ndvi_std")
    end

    test "vector item renders the table schema and links https alternates", %{conn: conn} do
      html =
        conn
        |> get("/stac/web/browse/collection/render-test-collection/item/render-vector")
        |> html_response(200)

      assert html =~ "Vector · 1 asset"
      assert html =~ "Table schema"
      assert html =~ "4,496,422"
      assert html =~ "wrb_code"
      assert html =~ "MultiLineString"
      assert html =~ "FlatGeobuf"
      assert html =~ ~s(href="https://example.org/ditches.gpkg")
      assert html =~ "GeoPackage"
      assert html =~ "LGeo"
    end

    test "minimal item without properties, bbox or assets renders", %{conn: conn} do
      html =
        conn
        |> get("/stac/web/browse/collection/render-test-collection/item/render-minimal")
        |> html_response(200)

      assert html =~ "render-minimal"
      assert html =~ "No assets available"
      assert html =~ "no datetime"
      refute html =~ "Projection</h2>"
      refute html =~ "Table schema"
    end

    test "collection page lists items by start date with range and asset count", %{conn: conn} do
      html =
        conn |> get("/stac/web/browse/collection/render-test-collection") |> html_response(200)

      assert html =~ "Temporal extent"
      assert html =~ "Spatial extent"
      assert html =~ "https://spdx.org/licenses/CC-BY-4.0.html"
      assert html =~ "Coverage"
      assert html =~ "2017-01-01 → 2025-12-31"
      assert html =~ "3 assets"
      assert html =~ "1 asset"

      assert index_of(html, "render-raster-single") <
               index_of(html, "render-raster-multi")

      assert index_of(html, "render-raster-multi") < index_of(html, "render-vector")
      assert index_of(html, "render-vector") < index_of(html, "render-minimal")
    end

    test "collection without extent, summaries or items renders", %{conn: conn} do
      insert_collection!("render-empty-collection",
        extent: nil,
        summaries: nil,
        keywords: nil,
        providers: nil
      )

      html =
        conn |> get("/stac/web/browse/collection/render-empty-collection") |> html_response(200)

      assert html =~ "render-empty-collection"
      assert html =~ "This collection contains no items"
    end
  end

  defp index_of(html, needle) do
    case :binary.match(html, needle) do
      {pos, _} -> pos
      :nomatch -> flunk("expected #{inspect(needle)} in html")
    end
  end

  defp insert_collection!(id, overrides \\ []) do
    attrs =
      Map.merge(
        %{
          id: id,
          title: "Render Test #{id}",
          description: "Rendering fixture",
          license: "CC-BY-4.0",
          keywords: ["fixture"],
          providers: [
            %{"name" => "Fixture Lab", "roles" => ["host"], "url" => "https://example.org"}
          ],
          summaries: %{"platform" => ["sentinel-2a"]},
          extent: %{
            "spatial" => %{"bbox" => [[21.0, 57.0, 28.0, 60.0]]},
            "temporal" => %{"interval" => [["2017-01-01T00:00:00Z", "2025-12-31T23:59:59Z"]]}
          }
        },
        Map.new(overrides)
      )

    %Collection{} |> Collection.changeset(attrs) |> Repo.insert!()
  end

  defp insert_item!(collection, id, opts) do
    polygon = %Geo.Polygon{
      coordinates: [[{21.0, 57.0}, {28.0, 57.0}, {28.0, 60.0}, {21.0, 60.0}, {21.0, 57.0}]],
      srid: 4326
    }

    attrs = %{
      id: id,
      collection_id: collection.id,
      geometry: polygon,
      bbox: Keyword.get(opts, :bbox, [21.0, 57.0, 28.0, 60.0]),
      stac_version: "1.0.0",
      stac_extensions: ["https://stac-extensions.github.io/raster/v1.1.0/schema.json"],
      datetime: nil,
      start_datetime: Keyword.get(opts, :start),
      end_datetime: Keyword.get(opts, :end),
      properties: Keyword.get(opts, :properties, %{})
    }

    item = %Item{} |> Item.changeset(attrs) |> Repo.insert!()

    for {key, asset} <- Keyword.get(opts, :assets, %{}) do
      item.id |> ItemAsset.from_stac_asset(key, asset) |> Repo.insert!()
    end

    item
  end

  defp cog_asset(name, roles) do
    %{
      "href" => "https://example.org/#{name}.tif",
      "type" => "image/tiff; application=geotiff; profile=cloud-optimized",
      "title" => String.capitalize(name),
      "roles" => roles,
      "file:size" => 1_944_156_840,
      "alternate" => %{
        "s3" => %{
          "href" => "s3://bucket/#{name}.tif",
          "type" => "image/tiff; application=geotiff; profile=cloud-optimized"
        }
      },
      "raster:bands" => [
        %{
          "data_type" => "float32",
          "nodata" => -9999.0,
          "spatial_resolution" => 10.0,
          "unit" => "metre",
          "sampling" => "area"
        }
      ]
    }
  end

  defp configured_read_only_key do
    :stac_api
    |> Application.get_env(:api_keys, %{})
    |> Map.get(:read_only, [])
    |> List.first()
  end
end
