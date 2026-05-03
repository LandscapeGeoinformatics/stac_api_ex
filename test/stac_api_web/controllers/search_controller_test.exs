defmodule StacApiWeb.SearchControllerTest do
  @moduledoc """
  Regression tests for STAC `datetime` filtering on:

    * /stac/api/v1/search  (SearchController)
    * /stac/web/search     (StacBrowserController)

  Original bug: `parse_datetime/1` only accepted full RFC 3339 strings with a
  timezone offset, so requests using date-only or `datetime-local` style
  values silently fell through with no filter applied. The web search form
  also submitted `datetime_start` / `datetime_end` as separate fields the
  search backend never read, so the date range was always ignored.
  """
  use StacApiWeb.ConnCase, async: true

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)

    post(auth_conn, ~p"/stac/manage/v1/catalogs", %{
      "id" => "search-test-catalog",
      "title" => "Search Test Catalog",
      "description" => "for datetime regression"
    })

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => "search-test-collection",
      "title" => "Search Test Collection",
      "description" => "for datetime regression",
      "license" => "CC-BY-4.0",
      "catalog_id" => "search-test-catalog",
      "extent" => %{
        "spatial" => %{"bbox" => [[-180, -90, 180, 90]]},
        "temporal" => %{
          "interval" => [["2022-01-01T00:00:00Z", "2024-12-31T23:59:59Z"]]
        }
      }
    })

    items = [
      {"item-2022", "2022-06-15T12:00:00Z"},
      {"item-2023", "2023-06-15T12:00:00Z"},
      {"item-2024", "2024-06-15T12:00:00Z"}
    ]

    Enum.each(items, fn {id, dt} ->
      post(auth_conn, ~p"/stac/manage/v1/items", %{
        "id" => id,
        "collection_id" => "search-test-collection",
        "stac_version" => "1.0.0",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => dt,
        "properties" => %{"description" => id}
      })
    end)

    {:ok, conn: build_conn(), auth_conn: auth_conn}
  end

  defp ids(response) do
    response["features"] |> Enum.map(& &1["id"]) |> Enum.sort()
  end

  describe "GET /stac/api/v1/search — datetime filter" do
    test "fully-qualified RFC 3339 range filters items", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "2023-01-01T00:00:00Z/2023-12-31T23:59:59Z"
        })

      response = json_response(conn, 200)
      assert ids(response) == ["item-2023"]
      assert response["context"]["matched"] == 1
    end

    test "open-ended start (../end) filters items", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "../2022-12-31T23:59:59Z"
        })

      assert ids(json_response(conn, 200)) == ["item-2022"]
    end

    test "open-ended end (start/..) filters items", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "2024-01-01T00:00:00Z/.."
        })

      assert ids(json_response(conn, 200)) == ["item-2024"]
    end

    test "date-only range is interpreted as UTC midnight", %{conn: conn} do
      # Regression: previously dropped silently, returning all items.
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "2023-01-01/2023-12-31"
        })

      assert ids(json_response(conn, 200)) == ["item-2023"]
    end

    test "datetime-local style range (no seconds, no offset) filters items", %{conn: conn} do
      # Regression: previously dropped silently — DateTime.from_iso8601 rejects
      # values without a timezone offset, so the filter was a no-op.
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "2023-01-01T00:00/2023-12-31T23:59"
        })

      assert ids(json_response(conn, 200)) == ["item-2023"]
    end

    test "POST search with JSON body and datetime range", %{conn: conn} do
      conn =
        post(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection",
          "datetime" => "2024-01-01T00:00:00Z/2024-12-31T23:59:59Z"
        })

      assert ids(json_response(conn, 200)) == ["item-2024"]
    end

    test "missing datetime returns all items in the collection", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "search-test-collection"
        })

      assert ids(json_response(conn, 200)) == ["item-2022", "item-2023", "item-2024"]
    end
  end

  describe "GET /stac/web/search — form datetime_start/datetime_end" do
    # The browser form posts a GET with `datetime_start` / `datetime_end`
    # rendered by HTML <input type="datetime-local"> controls (no offset).
    # Regression: these were forwarded verbatim and the search backend
    # ignored them — so the date-range filter on the web UI was a no-op.
    test "datetime_start + datetime_end narrow the results", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/web/search", %{
          "collections" => "search-test-collection",
          "datetime_start" => "2023-01-01T00:00",
          "datetime_end" => "2023-12-31T23:59"
        })

      html = html_response(conn, 200)
      assert html =~ "item-2023"
      refute html =~ "item-2022"
      refute html =~ "item-2024"
    end

    test "only datetime_start applied", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/web/search", %{
          "collections" => "search-test-collection",
          "datetime_start" => "2024-01-01T00:00"
        })

      html = html_response(conn, 200)
      assert html =~ "item-2024"
      refute html =~ "item-2022"
      refute html =~ "item-2023"
    end

    test "only datetime_end applied", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/web/search", %{
          "collections" => "search-test-collection",
          "datetime_end" => "2022-12-31T23:59"
        })

      html = html_response(conn, 200)
      assert html =~ "item-2022"
      refute html =~ "item-2023"
      refute html =~ "item-2024"
    end
  end

  describe "GET /stac/web/search/api — JSON variant of the form search" do
    test "datetime_start + datetime_end narrow the JSON results", %{conn: conn} do
      conn =
        get(conn, ~p"/stac/web/search/api", %{
          "collections" => "search-test-collection",
          "datetime_start" => "2023-01-01T00:00",
          "datetime_end" => "2023-12-31T23:59"
        })

      assert ids(json_response(conn, 200)) == ["item-2023"]
    end
  end
end
