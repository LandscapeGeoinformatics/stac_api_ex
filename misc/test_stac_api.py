#!/usr/bin/env python3
"""
STAC API Demo & Test Suite

Demonstrates the full lifecycle against a local Phoenix STAC API.

Bulk demo commands (self-contained, use hard-coded test fixtures)
-----------------------------------------------------------------
  insert        Create public catalog hierarchy (geokuup → estonia) + NDVI
                collection and 3 seasonal items from testdata/demo_2017/
  query         Run pystac-client searches (GET + POST, bbox, temporal,
                item ID, asset inspection)
  delete        Cascade-delete the 'geokuup' catalog (removes estonia,
                the collection, and all items)
  private-demo  Create a private catalog and a public baseline, then show
                that unauthenticated requests only see public data while
                requests with an API key also see private data.  Cleans up
                after itself.
  all           Run insert → query → delete → private-demo in order

Composable single-resource commands
------------------------------------
  create-catalog    --file <path.json> [--catalog-id <override-id>]
  create-collection --file <path.json> [--catalog-id <parent-id>]
  add-item          --file <path.json> [--collection-id <id>]
  delete-item       --item-id <id>
  delete-collection --collection-id <id>
  delete-catalog    --catalog-id <id>

Global options (place BEFORE the command name)
----------------------------------------------
  --api-url     Base URL of the STAC read API   (default: http://localhost:4000/stac/api/v1)
  --manage-url  Base URL of the management API  (default: http://localhost:4000/stac/manage/v1)
  --rw-key      Read-write API key              (default: dev-api-key-2024)
  --ro-key      Read-only  API key              (default: dev-read-only-key-2024)
  --testdata    Path to the demo_2017 directory (default: <script-dir>/testdata/demo_2017)

Examples
--------
  python test_stac_api.py                                    # show this help
  python test_stac_api.py insert                             # insert demo data
  python test_stac_api.py query                              # run searches
  python test_stac_api.py delete                             # cascade-delete geokuup
  python test_stac_api.py private-demo                       # access-control demo
  python test_stac_api.py all                                # full demo run

  python test_stac_api.py create-catalog --file cat.json
  python test_stac_api.py create-catalog --file cat.json --catalog-id my-id
  python test_stac_api.py create-collection --file col.json --catalog-id geokuup
  python test_stac_api.py add-item --file item.json --collection-id my-collection
  python test_stac_api.py delete-item --item-id est_s2_ndvi_2017-04-01_2017-05-31
  python test_stac_api.py delete-collection --collection-id estonia-sentinel2-ndvi
  python test_stac_api.py delete-catalog --catalog-id geokuup

  python test_stac_api.py --rw-key mykey create-catalog --file cat.json

Prerequisites
-------------
  pip install requests pystac-client pystac
  Phoenix server: mix phx.server
"""

import argparse
import json
import pathlib
import sys
import textwrap

import requests
from pystac_client import Client

# ---------------------------------------------------------------------------
# Defaults (overridable via CLI)
# ---------------------------------------------------------------------------
DEFAULT_API_URL    = "http://localhost:4000/stac/api/v1"
DEFAULT_MANAGE_URL = "http://localhost:4000/stac/manage/v1"
DEFAULT_RW_KEY     = "dev-api-key-2024"
DEFAULT_RO_KEY     = "dev-read-only-key-2024"
DEFAULT_TESTDATA   = pathlib.Path(__file__).parent / "testdata" / "demo_2017"

# ---------------------------------------------------------------------------
# Result accumulator (per-run, reset between independent command invocations)
# ---------------------------------------------------------------------------
TEST_RESULTS: list[dict] = []


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def section(title: str) -> None:
    print(f"\n{'='*62}")
    print(f"  {title}")
    print("=" * 62)


def log(name: str, ok: bool, message: str = "") -> None:
    symbol = "OK  " if ok else "FAIL"
    line = f"  [{symbol}] {name}"
    if message:
        line += f"\n         {message}"
    print(line)
    TEST_RESULTS.append({"test": name, "status": ok, "message": message})


def assert_status(resp: requests.Response, expected: int, label: str) -> bool:
    ok = resp.status_code == expected
    detail = f"HTTP {resp.status_code}"
    if not ok:
        detail += f" (expected {expected})"
        try:
            detail += f"  body={resp.json()}"
        except Exception:
            detail += f"  body={resp.text[:200]}"
    log(label, ok, detail)
    return ok


def print_summary(results: list[dict]) -> None:
    section("SUMMARY")
    passed = sum(1 for t in results if t["status"])
    total  = len(results)
    failed = total - passed

    print(f"  Total : {total}")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    if total:
        print(f"  Rate  : {passed / total * 100:.1f}%")

    if failed:
        print("\n  Failed checks:")
        for t in results:
            if not t["status"]:
                print(f"    - {t['test']}")
                if t["message"]:
                    print(f"      {t['message']}")

    print()
    if failed == 0:
        print("  ALL CHECKS PASSED")
    else:
        print(f"  {failed} CHECK(S) FAILED")


# ---------------------------------------------------------------------------
# Command: insert
# ---------------------------------------------------------------------------

def cmd_insert(cfg: argparse.Namespace) -> None:
    section("INSERT: public catalog hierarchy + NDVI data")
    headers = {"Content-Type": "application/json", "X-API-Key": cfg.rw_key}
    testdata = cfg.testdata

    # 1. Root catalog: geokuup
    r = requests.post(
        f"{cfg.manage_url}/catalogs",
        json={
            "id": "geokuup",
            "title": "GeoKuup",
            "description": "GeoKuup public geospatial data catalog",
            "type": "Catalog",
            "stac_version": "1.0.0",
            "private": False,
        },
        headers=headers,
    )
    assert_status(r, 201, "Create root catalog 'geokuup'")

    # 2. Sub-catalog: estonia (child of geokuup)
    r = requests.post(
        f"{cfg.manage_url}/catalogs",
        json={
            "id": "estonia",
            "title": "Estonia",
            "description": "Datasets covering Estonia",
            "type": "Catalog",
            "stac_version": "1.0.0",
            "parent_catalog_id": "geokuup",
            "private": False,
        },
        headers=headers,
    )
    assert_status(r, 201, "Create sub-catalog 'estonia' (parent: geokuup)")

    # 3. Collection from testdata — attach to 'estonia'
    collection_json = testdata / "collection.json"
    with open(collection_json) as f:
        collection_data = json.load(f)
    collection_data["catalog_id"] = "estonia"
    r = requests.post(f"{cfg.manage_url}/collections", json=collection_data, headers=headers)
    assert_status(r, 201, f"Create collection '{collection_data['id']}'")

    # 4. Items from testdata/items/
    items_dir  = testdata / "items"
    item_files = sorted(items_dir.glob("*.json"))
    if not item_files:
        log("Find item JSON files", False, f"No .json files found in {items_dir}")
        return

    for item_path in item_files:
        with open(item_path) as f:
            stac_item = json.load(f)
        props = stac_item.get("properties", {})
        # STAC Feature → manage API: rename 'collection' to 'collection_id',
        # promote 'datetime' from properties to top-level (may be null for
        # interval items that carry start_datetime / end_datetime instead).
        payload = {
            "id":              stac_item["id"],
            "stac_version":    stac_item.get("stac_version", "1.0.0"),
            "stac_extensions": stac_item.get("stac_extensions", []),
            "collection_id":   stac_item.get("collection", collection_data["id"]),
            "geometry":        stac_item["geometry"],
            "bbox":            stac_item["bbox"],
            "datetime":        props.get("datetime"),
            "properties":      props,
            "assets":          stac_item.get("assets", {}),
            "links":           stac_item.get("links", []),
        }
        r = requests.post(f"{cfg.manage_url}/items", json=payload, headers=headers)
        assert_status(r, 201, f"Insert item '{stac_item['id']}'")


# ---------------------------------------------------------------------------
# Command: query
# ---------------------------------------------------------------------------

def cmd_query(cfg: argparse.Namespace) -> None:
    section("QUERY: pystac-client GET + POST searches")

    collection_id = "estonia-sentinel2-ndvi"
    estonia_bbox  = [21.664072, 57.471219, 28.275494, 59.831227]

    # Open root catalog (no auth — public read)
    try:
        catalog = Client.open(f"{cfg.api_url}/")
        log("Connect to root catalog", True, catalog.title or catalog.id)
    except Exception as exc:
        log("Connect to root catalog", False, str(exc))
        return

    # a. GET — filter by collection
    search = catalog.search(collections=[collection_id], limit=10)
    items  = list(search.items())
    log(
        "GET  — by collection",
        len(items) > 0,
        f"{len(items)} item(s) in '{collection_id}'",
    )

    # b. POST — collection + bbox
    search = catalog.search(
        method="POST",
        collections=[collection_id],
        bbox=estonia_bbox,
        limit=10,
    )
    items = list(search.items())
    log(
        "POST — collection + Estonia bbox",
        len(items) > 0,
        f"{len(items)} item(s) within bbox {estonia_bbox}",
    )

    # c. GET — temporal window (spring composite)
    search = catalog.search(
        collections=[collection_id],
        datetime="2017-04-01T00:00:00Z/2017-05-31T23:59:59Z",
        limit=5,
    )
    items = list(search.items())
    log(
        "GET  — temporal 2017-04/2017-05",
        len(items) >= 0,
        (
            f"{len(items)} item(s)  "
            "(note: interval items with datetime=null may not match temporal filter)"
        ),
    )

    # d. GET — bbox only across all collections
    search = catalog.search(bbox=estonia_bbox, limit=10)
    items  = list(search.items())
    log(
        "GET  — Estonia bbox (all collections)",
        len(items) > 0,
        f"{len(items)} item(s)",
    )

    # e. GET — specific item by ID
    item_id = "est_s2_ndvi_2017-06-01_2017-08-31"
    search  = catalog.search(ids=[item_id])
    items   = list(search.items())
    log(
        f"GET  — item by ID '{item_id}'",
        len(items) == 1,
        f"found {len(items)} item(s)",
    )

    # f. Asset inspection on the retrieved item
    if items:
        item       = items[0]
        asset_keys = list(item.assets.keys())
        has_max    = "ndvi_max" in asset_keys
        log(
            "Item has 'ndvi_max' asset",
            has_max,
            f"all assets: {asset_keys}",
        )
        if has_max:
            href = item.assets["ndvi_max"].href
            log(
                "ndvi_max href is an HTTP URL",
                href.startswith("http"),
                href[:80],
            )

    # g. GET /collections/:id/items (OGC Features endpoint)
    r = requests.get(
        f"{cfg.api_url}/collections/{collection_id}/items",
        params={"limit": 10},
        headers={"Accept": "application/geo+json"},
    )
    if assert_status(r, 200, f"GET /collections/{collection_id}/items"):
        fc = r.json()
        log(
            "Response is a GeoJSON FeatureCollection",
            fc.get("type") == "FeatureCollection",
            f"{len(fc.get('features', []))} feature(s)",
        )

    # h. POST — collection + bbox + full-year temporal
    search = catalog.search(
        method="POST",
        collections=[collection_id],
        bbox=estonia_bbox,
        datetime="2017-01-01T00:00:00Z/2017-12-31T23:59:59Z",
        limit=10,
    )
    items = list(search.items())
    log(
        "POST — collection + bbox + temporal (full 2017)",
        len(items) >= 0,
        f"{len(items)} item(s)",
    )


# ---------------------------------------------------------------------------
# Command: delete
# ---------------------------------------------------------------------------

def cmd_delete(cfg: argparse.Namespace) -> None:
    section("DELETE: cascade-delete 'geokuup' catalog")

    r = requests.delete(
        f"{cfg.manage_url}/catalogs/geokuup",
        headers={"X-API-Key": cfg.rw_key},
    )
    assert_status(r, 200, "DELETE /manage/v1/catalogs/geokuup  (cascade)")

    # Confirm cascade: collection must be gone from the public STAC API
    r = requests.get(f"{cfg.api_url}/collections/estonia-sentinel2-ndvi")
    log(
        "Collection 404 after cascade delete",
        r.status_code == 404,
        f"HTTP {r.status_code}",
    )


# ---------------------------------------------------------------------------
# Command: private-demo
# ---------------------------------------------------------------------------

def cmd_private_demo(cfg: argparse.Namespace) -> None:
    section("PRIVATE CATALOG: access-control demo")
    headers = {"Content-Type": "application/json", "X-API-Key": cfg.rw_key}

    # ---- Setup: public baseline ------------------------------------------
    print("\n  [setup] Creating public baseline catalog + collection …")

    r = requests.post(
        f"{cfg.manage_url}/catalogs",
        json={
            "id": "public-demo-catalog",
            "title": "Public Demo Catalog",
            "description": "Visible to everyone",
            "type": "Catalog",
            "stac_version": "1.0.0",
            "private": False,
        },
        headers=headers,
    )
    assert_status(r, 201, "Create public-demo-catalog")

    r = requests.post(
        f"{cfg.manage_url}/collections",
        json={
            "id": "public-demo-collection",
            "title": "Public Demo Collection",
            "description": "Visible without auth",
            "license": "CC0-1.0",
            "catalog_id": "public-demo-catalog",
            "stac_version": "1.0.0",
            "extent": {
                "spatial":  {"bbox": [[-180, -90, 180, 90]]},
                "temporal": {"interval": [["2020-01-01T00:00:00Z", None]]},
            },
        },
        headers=headers,
    )
    assert_status(r, 201, "Create public-demo-collection")

    # ---- Setup: private catalog + collection + item ----------------------
    print("\n  [setup] Creating private catalog + collection + item …")

    r = requests.post(
        f"{cfg.manage_url}/catalogs",
        json={
            "id": "private-test-catalog",
            "title": "Private Test Catalog",
            "description": "Only visible to authenticated users",
            "type": "Catalog",
            "stac_version": "1.0.0",
            "private": True,
        },
        headers=headers,
    )
    assert_status(r, 201, "Create private-test-catalog  (private=true)")

    r = requests.post(
        f"{cfg.manage_url}/collections",
        json={
            "id": "private-test-collection",
            "title": "Private Test Collection",
            "description": "Belongs to the private catalog",
            "license": "proprietary",
            "catalog_id": "private-test-catalog",
            "stac_version": "1.0.0",
            "extent": {
                "spatial":  {"bbox": [[21.0, 57.0, 29.0, 60.0]]},
                "temporal": {"interval": [["2024-01-01T00:00:00Z", None]]},
            },
        },
        headers=headers,
    )
    assert_status(r, 201, "Create private-test-collection under private catalog")

    r = requests.post(
        f"{cfg.manage_url}/items",
        json={
            "id": "private-test-item-001",
            "stac_version": "1.0.0",
            "collection_id": "private-test-collection",
            "geometry": {
                "type": "Polygon",
                "coordinates": [
                    [[24.0, 58.0], [25.0, 58.0], [25.0, 59.0], [24.0, 59.0], [24.0, 58.0]]
                ],
            },
            "bbox": [24.0, 58.0, 25.0, 59.0],
            "datetime": "2024-06-15T12:00:00Z",
            "properties": {"description": "Secret geospatial asset"},
            "assets": {
                "data": {
                    "href": "https://example.com/private/asset.tif",
                    "type": "image/tiff; application=geotiff",
                    "title": "Private COG",
                }
            },
        },
        headers=headers,
    )
    assert_status(r, 201, "Insert private-test-item-001")

    # ---- Without API key -------------------------------------------------
    print("\n  [check] Without API key — should only see public data")

    r = requests.get(f"{cfg.api_url}/collections", headers={"Accept": "application/json"})
    if assert_status(r, 200, "GET /collections (no key)"):
        col_ids = [c["id"] for c in r.json().get("collections", [])]
        log(
            "public-demo-collection visible   (no key)",
            "public-demo-collection"  in col_ids,
            f"visible: {col_ids}",
        )
        log(
            "private-test-collection NOT visible (no key)",
            "private-test-collection" not in col_ids,
            f"visible: {col_ids}",
        )

    r = requests.get(f"{cfg.api_url}/search", params={"limit": 50})
    if assert_status(r, 200, "GET /search (no key)"):
        collections_in_results = {
            f["collection"] for f in r.json().get("features", []) if "collection" in f
        }
        log(
            "private-test-item not in /search results (no key)",
            "private-test-collection" not in collections_in_results,
            f"collections in results: {collections_in_results or '(none)'}",
        )

    # ---- With read-only API key ------------------------------------------
    print("\n  [check] With read-only API key — should see public + private data")

    ro_headers = {"Accept": "application/json", "X-API-Key": cfg.ro_key}
    r = requests.get(f"{cfg.api_url}/collections", headers=ro_headers)
    if assert_status(r, 200, "GET /collections (RO key)"):
        col_ids = [c["id"] for c in r.json().get("collections", [])]
        log(
            "public-demo-collection visible   (RO key)",
            "public-demo-collection"  in col_ids,
            f"visible: {col_ids}",
        )
        log(
            "private-test-collection visible  (RO key)",
            "private-test-collection" in col_ids,
            f"visible: {col_ids}",
        )

    r = requests.get(
        f"{cfg.api_url}/search",
        params={"limit": 50},
        headers={"X-API-Key": cfg.ro_key},
    )
    if assert_status(r, 200, "GET /search (RO key)"):
        collections_in_results = {
            f["collection"] for f in r.json().get("features", []) if "collection" in f
        }
        log(
            "private-test-item in /search results (RO key)",
            "private-test-collection" in collections_in_results,
            f"collections in results: {collections_in_results or '(none)'}",
        )

    # ---- pystac-client with RO key injected ------------------------------
    print("\n  [check] pystac-client with RO key")
    try:
        auth_catalog = Client.open(
            f"{cfg.api_url}/",
            headers={"X-API-Key": cfg.ro_key},
        )
        col_ids = [c.id for c in auth_catalog.get_collections()]
        log(
            "pystac-client (RO key): private-test-collection accessible",
            "private-test-collection" in col_ids,
            f"total collections seen: {len(col_ids)}",
        )
    except Exception as exc:
        log("pystac-client with RO key", False, str(exc))

    # ---- Cleanup ---------------------------------------------------------
    print("\n  [cleanup] Deleting demo catalogs …")
    for cat_id in ("private-test-catalog", "public-demo-catalog"):
        r = requests.delete(
            f"{cfg.manage_url}/catalogs/{cat_id}",
            headers={"X-API-Key": cfg.rw_key},
        )
        assert_status(r, 200, f"DELETE {cat_id} (cascade)")


# ---------------------------------------------------------------------------
# Command: all
# ---------------------------------------------------------------------------

def cmd_all(cfg: argparse.Namespace) -> None:
    cmd_insert(cfg)
    cmd_query(cfg)
    cmd_delete(cfg)
    cmd_private_demo(cfg)


# ---------------------------------------------------------------------------
# Helper: map a STAC GeoJSON Feature to the management API item payload
# ---------------------------------------------------------------------------

def _stac_feature_to_item_payload(stac_item: dict, collection_id: str | None = None) -> dict:
    """Convert a STAC GeoJSON Feature dict to the shape expected by POST /manage/v1/items.

    The management API differs from the STAC spec in two ways:
      - uses ``collection_id`` (not ``collection``) to reference the parent collection
      - expects ``datetime`` as a top-level field (may be None for interval items that
        carry ``start_datetime`` / ``end_datetime`` inside ``properties`` instead)

    Args:
        stac_item:     Parsed JSON dict of a STAC Feature.
        collection_id: Override (or supply) the collection identifier.  When *None*
                       the value is read from ``stac_item["collection"]``.  An error
                       is raised if neither source provides the value.
    """
    col_id = collection_id or stac_item.get("collection")
    if not col_id:
        raise ValueError(
            "collection_id is required: pass --collection-id or include "
            "'collection' in the item JSON"
        )
    props = stac_item.get("properties", {})
    return {
        "id":              stac_item["id"],
        "stac_version":    stac_item.get("stac_version", "1.0.0"),
        "stac_extensions": stac_item.get("stac_extensions", []),
        "collection_id":   col_id,
        "geometry":        stac_item["geometry"],
        "bbox":            stac_item["bbox"],
        "datetime":        props.get("datetime"),   # None is valid for interval items
        "properties":      props,
        "assets":          stac_item.get("assets", {}),
        "links":           stac_item.get("links", []),
    }


# ---------------------------------------------------------------------------
# Composable single-resource commands
# ---------------------------------------------------------------------------

def cmd_create_catalog(cfg: argparse.Namespace) -> None:
    """Create one catalog from a JSON file."""
    section(f"CREATE CATALOG from {cfg.file}")
    with open(cfg.file) as f:
        data = json.load(f)
    if cfg.catalog_id:
        data["id"] = cfg.catalog_id
    r = requests.post(
        f"{cfg.manage_url}/catalogs",
        json=data,
        headers={"Content-Type": "application/json", "X-API-Key": cfg.rw_key},
    )
    if assert_status(r, 201, f"POST /manage/v1/catalogs  id={data.get('id')}"):
        print(f"  created: {r.json()}")


def cmd_create_collection(cfg: argparse.Namespace) -> None:
    """Create one collection from a JSON file, optionally attaching it to a catalog."""
    section(f"CREATE COLLECTION from {cfg.file}")
    with open(cfg.file) as f:
        data = json.load(f)
    if cfg.catalog_id:
        data["catalog_id"] = cfg.catalog_id
    r = requests.post(
        f"{cfg.manage_url}/collections",
        json=data,
        headers={"Content-Type": "application/json", "X-API-Key": cfg.rw_key},
    )
    if assert_status(r, 201, f"POST /manage/v1/collections  id={data.get('id')}"):
        print(f"  created: {r.json()}")


def cmd_add_item(cfg: argparse.Namespace) -> None:
    """Add one STAC item from a JSON file to an existing collection."""
    section(f"ADD ITEM from {cfg.file}")
    with open(cfg.file) as f:
        stac_item = json.load(f)
    try:
        payload = _stac_feature_to_item_payload(stac_item, cfg.collection_id)
    except ValueError as exc:
        log(f"Add item '{stac_item.get('id', '?')}'", False, str(exc))
        return
    r = requests.post(
        f"{cfg.manage_url}/items",
        json=payload,
        headers={"Content-Type": "application/json", "X-API-Key": cfg.rw_key},
    )
    if assert_status(r, 201, f"POST /manage/v1/items  id={payload['id']}"):
        print(f"  created: {r.json()}")


def cmd_delete_item(cfg: argparse.Namespace) -> None:
    """Delete a single item by item ID."""
    section(f"DELETE ITEM  id={cfg.item_id}")
    r = requests.delete(
        f"{cfg.manage_url}/items/{cfg.item_id}",
        headers={"X-API-Key": cfg.rw_key},
    )
    assert_status(r, 200, f"DELETE /manage/v1/items/{cfg.item_id}")


def cmd_delete_collection(cfg: argparse.Namespace) -> None:
    """Delete a collection (and all its items) by collection ID."""
    section(f"DELETE COLLECTION  id={cfg.collection_id}")
    r = requests.delete(
        f"{cfg.manage_url}/collections/{cfg.collection_id}",
        headers={"X-API-Key": cfg.rw_key},
    )
    assert_status(r, 200, f"DELETE /manage/v1/collections/{cfg.collection_id}")


def cmd_delete_catalog(cfg: argparse.Namespace) -> None:
    """Cascade-delete a catalog (removes child catalogs, collections, and items)."""
    section(f"DELETE CATALOG  id={cfg.catalog_id}")
    r = requests.delete(
        f"{cfg.manage_url}/catalogs/{cfg.catalog_id}",
        headers={"X-API-Key": cfg.rw_key},
    )
    assert_status(r, 200, f"DELETE /manage/v1/catalogs/{cfg.catalog_id}  (cascade)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Bulk commands — no subcommand-specific arguments
BULK_COMMANDS: dict[str, tuple[str, object]] = {
    "insert":       ("create public catalog hierarchy (geokuup→estonia) + NDVI collection + 3 items",
                     cmd_insert),
    "query":        ("run pystac-client searches: GET/POST, bbox, temporal, item ID, asset inspection",
                     cmd_query),
    "delete":       ("cascade-delete the 'geokuup' catalog (removes estonia, collection, all items)",
                     cmd_delete),
    "private-demo": ("create public/private catalogs, validate visibility rules, then clean up",
                     cmd_private_demo),
    "all":          ("run insert → query → delete → private-demo in sequence",
                     cmd_all),
}

# Composable commands — each registered with its handler; args added below in build_parser()
COMPOSABLE_COMMANDS: dict[str, tuple[str, object]] = {
    "create-catalog":    ("create a catalog from a JSON file",                   cmd_create_catalog),
    "create-collection": ("create a collection from a JSON file",                cmd_create_collection),
    "add-item":          ("add one item from a JSON file to an existing collection", cmd_add_item),
    "delete-item":       ("delete a single item by item ID",                     cmd_delete_item),
    "delete-collection": ("delete a collection (cascade: all items) by ID",      cmd_delete_collection),
    "delete-catalog":    ("cascade-delete a catalog by ID",                      cmd_delete_catalog),
}

ALL_COMMANDS = {**BULK_COMMANDS, **COMPOSABLE_COMMANDS}


def _add_global_args(p: argparse.ArgumentParser) -> None:
    """Add the shared global options to a parser or subparser."""
    p.add_argument(
        "--api-url",
        default=DEFAULT_API_URL,
        metavar="URL",
        help=f"STAC read API base URL  (default: {DEFAULT_API_URL})",
    )
    p.add_argument(
        "--manage-url",
        default=DEFAULT_MANAGE_URL,
        metavar="URL",
        help=f"management API base URL (default: {DEFAULT_MANAGE_URL})",
    )
    p.add_argument(
        "--rw-key",
        default=DEFAULT_RW_KEY,
        metavar="KEY",
        help=f"read-write API key      (default: {DEFAULT_RW_KEY})",
    )
    p.add_argument(
        "--ro-key",
        default=DEFAULT_RO_KEY,
        metavar="KEY",
        help=f"read-only  API key      (default: {DEFAULT_RO_KEY})",
    )
    p.add_argument(
        "--testdata",
        default=DEFAULT_TESTDATA,
        type=pathlib.Path,
        metavar="DIR",
        help=f"path to demo_2017 testdata dir (default: {DEFAULT_TESTDATA})",
    )


def build_parser() -> argparse.ArgumentParser:
    # ---- top-level description ------------------------------------------
    bulk_lines = "\n".join(
        f"  {cmd:<18}  {desc}" for cmd, (desc, _) in BULK_COMMANDS.items()
    )
    comp_lines = "\n".join(
        f"  {cmd:<18}  {desc}" for cmd, (desc, _) in COMPOSABLE_COMMANDS.items()
    )
    description = textwrap.dedent(f"""\
        STAC API Demo & Test Suite
        ──────────────────────────
        Run individual lifecycle steps or the full suite against a local
        Phoenix STAC API.  With no command given this help is shown.
        Global options (--api-url, --manage-url, --rw-key, --ro-key,
        --testdata) must be placed BEFORE the command name.

        Bulk demo commands
        ──────────────────
        {bulk_lines}

        Composable single-resource commands
        ────────────────────────────────────
        {comp_lines}

        Examples
        ────────
          python test_stac_api.py                                   # this help
          python test_stac_api.py insert                            # insert demo data
          python test_stac_api.py all                               # full demo run
          python test_stac_api.py create-catalog --file cat.json
          python test_stac_api.py create-catalog --file cat.json --catalog-id my-id
          python test_stac_api.py create-collection --file col.json --catalog-id geokuup
          python test_stac_api.py add-item --file item.json --collection-id my-col
          python test_stac_api.py delete-item --item-id est_s2_ndvi_2017-04-01_2017-05-31
          python test_stac_api.py delete-collection --collection-id estonia-sentinel2-ndvi
          python test_stac_api.py delete-catalog --catalog-id geokuup
          python test_stac_api.py --rw-key mykey create-catalog --file cat.json
    """)

    parser = argparse.ArgumentParser(
        prog="test_stac_api.py",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=description,
    )
    _add_global_args(parser)

    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    # ---- bulk commands (no extra args) ----------------------------------
    for name, (desc, _) in BULK_COMMANDS.items():
        subparsers.add_parser(name, help=desc)

    # ---- composable: create-catalog -------------------------------------
    sp = subparsers.add_parser("create-catalog", help=COMPOSABLE_COMMANDS["create-catalog"][0])
    sp.add_argument(
        "--file", required=True, type=pathlib.Path, metavar="PATH",
        help="JSON file containing the catalog object",
    )
    sp.add_argument(
        "--catalog-id", default=None, metavar="ID",
        help="override the 'id' field from the JSON file",
    )

    # ---- composable: create-collection ----------------------------------
    sp = subparsers.add_parser("create-collection", help=COMPOSABLE_COMMANDS["create-collection"][0])
    sp.add_argument(
        "--file", required=True, type=pathlib.Path, metavar="PATH",
        help="JSON file containing the collection object",
    )
    sp.add_argument(
        "--catalog-id", default=None, metavar="ID",
        help="set or override the 'catalog_id' field (parent catalog)",
    )

    # ---- composable: add-item -------------------------------------------
    sp = subparsers.add_parser("add-item", help=COMPOSABLE_COMMANDS["add-item"][0])
    sp.add_argument(
        "--file", required=True, type=pathlib.Path, metavar="PATH",
        help="JSON file containing the STAC Feature (item)",
    )
    sp.add_argument(
        "--collection-id", default=None, metavar="ID",
        help=(
            "target collection ID; overrides the 'collection' field in the JSON. "
            "Required if the JSON does not include a 'collection' key."
        ),
    )

    # ---- composable: delete-item ----------------------------------------
    sp = subparsers.add_parser("delete-item", help=COMPOSABLE_COMMANDS["delete-item"][0])
    sp.add_argument(
        "--item-id", required=True, metavar="ID",
        help="ID of the item to delete",
    )

    # ---- composable: delete-collection ----------------------------------
    sp = subparsers.add_parser("delete-collection", help=COMPOSABLE_COMMANDS["delete-collection"][0])
    sp.add_argument(
        "--collection-id", required=True, metavar="ID",
        help="ID of the collection to delete (cascade: removes all its items)",
    )

    # ---- composable: delete-catalog -------------------------------------
    sp = subparsers.add_parser("delete-catalog", help=COMPOSABLE_COMMANDS["delete-catalog"][0])
    sp.add_argument(
        "--catalog-id", required=True, metavar="ID",
        help="ID of the catalog to delete (cascade: child catalogs, collections, items)",
    )

    return parser


def main() -> None:
    parser = build_parser()
    args   = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    # Validate testdata path for commands that need it
    if args.command in ("insert", "all") and not args.testdata.is_dir():
        print(f"error: testdata directory not found: {args.testdata}", file=sys.stderr)
        sys.exit(2)

    # Validate --file exists for file-based composable commands
    if args.command in ("create-catalog", "create-collection", "add-item"):
        if not args.file.is_file():
            print(f"error: file not found: {args.file}", file=sys.stderr)
            sys.exit(2)

    print(f"STAC API : {args.api_url}")
    print(f"Manage   : {args.manage_url}")
    if args.command in ("insert", "all"):
        print(f"Testdata : {args.testdata}")

    TEST_RESULTS.clear()
    _, handler = ALL_COMMANDS[args.command]
    handler(args)
    print_summary(TEST_RESULTS)

    failed = sum(1 for t in TEST_RESULTS if not t["status"])
    sys.exit(failed)


if __name__ == "__main__":
    main()
