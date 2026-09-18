defmodule StacApiWeb.StacBrowserHelpersTest do
  use ExUnit.Case, async: true

  alias StacApiWeb.StacBrowserHelpers, as: H

  describe "temporal_range/1" do
    test "prefers datetime over a range" do
      assert {:instant, %DateTime{year: 2020}} =
               H.temporal_range(%{
                 "datetime" => "2020-01-01T00:00:00Z",
                 "start_datetime" => "2019-01-01T00:00:00Z"
               })
    end

    test "returns a range when datetime is null" do
      assert {:range, %DateTime{year: 2017}, %DateTime{year: 2018}} =
               H.temporal_range(%{
                 "datetime" => nil,
                 "start_datetime" => "2017-09-01T00:00:00Z",
                 "end_datetime" => "2018-10-31T23:59:59Z"
               })
    end

    test "reads struct-style atom keys and falls back to nested properties" do
      assert {:range, nil, %DateTime{year: 2025}} =
               H.temporal_range(%{properties: %{"end_datetime" => "2025-12-31T23:59:59Z"}})

      assert {:instant, %DateTime{}} = H.temporal_range(%{datetime: ~U[2021-05-05 10:00:00Z]})
    end

    test "tolerates garbage" do
      assert :none == H.temporal_range(%{"datetime" => "not a date"})
      assert :none == H.temporal_range(%{})
      assert :none == H.temporal_range(nil)
      assert :none == H.temporal_range("string")
    end
  end

  describe "duration_days/1" do
    test "counts inclusive days" do
      range =
        H.temporal_range(%{
          "start_datetime" => "2017-09-01T00:00:00Z",
          "end_datetime" => "2017-10-31T23:59:59Z"
        })

      assert H.duration_days(range) == 61
    end

    test "is nil for open or inverted ranges" do
      assert H.duration_days({:range, nil, ~U[2020-01-01 00:00:00Z]}) == nil
      assert H.duration_days({:range, ~U[2020-01-02 00:00:00Z], ~U[2020-01-01 00:00:00Z]}) == nil
      assert H.duration_days(:none) == nil
    end
  end

  describe "format_bytes/1 and format_int/1" do
    test "scales units" do
      assert H.format_bytes(1_944_156_840) == "1.9 GB"
      assert H.format_bytes(847_832_320) == "847.8 MB"
      assert H.format_bytes(18_179_766) == "18.2 MB"
      assert H.format_bytes(512) == "512 B"
      assert H.format_bytes(nil) == "n/a"
      assert H.format_bytes("x") == "n/a"
    end

    test "thousands separators" do
      assert H.format_int(4_496_422) == "4,496,422"
      assert H.format_int(999) == "999"
      assert H.format_int(-1234) == "-1,234"
      assert H.format_int(nil) == "n/a"
    end
  end

  describe "media_type_label/1 and asset_kind/1" do
    test "maps common geo media types" do
      assert H.media_type_label("image/tiff; application=geotiff; profile=cloud-optimized") ==
               "COG GeoTIFF"

      assert H.media_type_label("image/tiff; application=geotiff") == "GeoTIFF"
      assert H.media_type_label("application/vnd.flatgeobuf") == "FlatGeobuf"
      assert H.media_type_label("application/geopackage+sqlite3") == "GeoPackage"
      assert H.media_type_label("application/x-parquet") == "GeoParquet"
      assert H.media_type_label(nil) == "unknown"
    end

    test "classifies assets" do
      assert H.asset_kind(%{"type" => "image/tiff; application=geotiff; profile=cloud-optimized"}) ==
               :raster

      assert H.asset_kind(%{"raster:bands" => []}) == :raster
      assert H.asset_kind(%{"type" => "application/vnd.flatgeobuf"}) == :vector
      assert H.asset_kind(%{"type" => "text/csv"}) == :table
      assert H.asset_kind(%{}) == :other
      assert H.asset_kind(nil) == :other
    end

    test "classifies items by their assets" do
      cog = %{"type" => "image/tiff; application=geotiff; profile=cloud-optimized"}
      assert H.item_kind(%{"data" => cog}) == :raster
      assert H.item_kind(%{"a" => cog, "b" => cog}) == :raster_multi
      assert H.item_kind(%{"data" => %{"type" => "application/vnd.flatgeobuf"}}) == :vector
      assert H.item_kind(%{}) == :other
      assert H.item_kind(nil) == :other
    end
  end

  describe "split_assets/1" do
    test "separates data assets from statistics/metadata and orders them" do
      assets = %{
        "std" => %{"roles" => ["metadata", "statistics"]},
        "max" => %{"roles" => ["data", "statistics"]},
        "median" => %{"roles" => ["data"]},
        "noroles" => %{}
      }

      {primary, aux} = H.split_assets(assets)
      assert Enum.map(primary, &elem(&1, 0)) == ["median", "max", "noroles"]
      assert Enum.map(aux, &elem(&1, 0)) == ["std"]
      assert H.auxiliary_group_label(aux) == "Statistics & metadata"
    end

    test "handles garbage" do
      assert H.split_assets(nil) == {[], []}
      assert {[{"x", %{}}], []} = H.split_assets(%{"x" => "not a map"})
    end
  end

  describe "group_properties/2" do
    test "groups core first, then known prefixes, then others" do
      props = %{
        "proj:code" => "EPSG:3301",
        "zzz:custom" => 1,
        "lgeo:driver" => "FlatGeobuf",
        "table:row_count" => 5,
        "title" => "T",
        "plain" => true,
        "datetime" => nil
      }

      groups = H.group_properties(props, skip: ["datetime"])

      assert Enum.map(groups, &elem(&1, 0)) == [
               "Core",
               "Projection",
               "Table",
               "LGeo",
               "Zzz",
               "Other"
             ]

      assert {"Core", [{"title", "T"}]} = hd(groups)
    end

    test "returns [] for non-maps" do
      assert H.group_properties(nil) == []
      assert H.group_properties([1, 2]) == []
    end
  end

  describe "proj_summary/1" do
    test "reads proj:code, shape, transform and bbox" do
      s =
        H.proj_summary(%{
          "proj:code" => "EPSG:3301",
          "proj:shape" => [25800, 37100],
          "proj:transform" => [369_000, 10.0, 0.0, 6_635_000, 0.0, -10.0],
          "proj:bbox" => [369_000, 6_377_000, 740_000, 6_635_000]
        })

      assert s.code == "EPSG:3301"
      assert s.epsg == 3301
      assert s.shape == {25800, 37100}
      assert s.pixel == {10.0, 10.0}
      assert s.origin == {369_000, 6_635_000}
      assert s.bbox == [369_000, 6_377_000, 740_000, 6_635_000]
      assert H.proj_present?(s)
    end

    test "accepts a 9-element transform, legacy proj:epsg and 3D bboxes" do
      s =
        H.proj_summary(%{
          "proj:epsg" => 4326,
          "proj:transform" => [0.0, 0.5, 0.0, 90.0, 0.0, -0.5, 0.0, 0.0, 1.0],
          "proj:bbox" => [1, 2, 0, 3, 4, 10]
        })

      assert s.code == "EPSG:4326"
      assert s.pixel == {0.5, 0.5}
      assert s.bbox == [1, 2, 3, 4]
    end

    test "is empty for missing or malformed input" do
      refute H.proj_present?(H.proj_summary(%{}))
      refute H.proj_present?(H.proj_summary(nil))
      s = H.proj_summary(%{"proj:shape" => "bad", "proj:transform" => "bad", "proj:bbox" => [1]})
      refute H.proj_present?(s)
    end
  end

  describe "collection extent helpers" do
    test "temporal_extent/1 and spatial_bbox/1" do
      extent = %{
        "spatial" => %{"bbox" => [[21.6, 57.4, 28.2, 59.8]]},
        "temporal" => %{"interval" => [["2017-04-01T00:00:00Z", nil]]}
      }

      assert {:range, %DateTime{year: 2017}, nil} = H.temporal_extent(extent)
      assert H.spatial_bbox(extent) == [21.6, 57.4, 28.2, 59.8]
      assert H.temporal_extent(nil) == :none
      assert H.spatial_bbox(%{"spatial" => %{}}) == nil
    end

    test "license_url/1 links SPDX identifiers only" do
      assert H.license_url("CC-BY-4.0") == "https://spdx.org/licenses/CC-BY-4.0.html"
      assert H.license_url("proprietary") == nil
      assert H.license_url("some free text") == nil
      assert H.license_url(nil) == nil
    end

    test "extension_label/1 shortens schema urls" do
      assert H.extension_label("https://stac-extensions.github.io/raster/v1.1.0/schema.json") ==
               "raster v1.1.0"

      assert H.extension_label("https://example.org/custom.json") ==
               "https://example.org/custom.json"
    end
  end
end
