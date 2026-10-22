#!/usr/bin/env python3
"""Demonstrate the STAC API Fields extension against one collection.

Example:
  python misc/demo_fields.py --collection estonia-sentinel2-ndvi

The script fetches one full Item and then repeats the request while excluding
``properties.table:columns``. It prints response sizes and verifies that the
requested nested field is absent from the filtered result.
"""

import argparse
import sys

import requests


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-url",
        default="http://localhost:4000/stac/api/v1",
        help="STAC API base URL (default: %(default)s)",
    )
    parser.add_argument("--collection", required=True, help="collection ID to query")
    parser.add_argument(
        "--exclude-path",
        default="properties.table:columns",
        help="nested STAC field path to exclude (default: %(default)s)",
    )
    return parser.parse_args()


def first_feature(response: requests.Response) -> dict:
    response.raise_for_status()
    features = response.json().get("features", [])
    if not features:
        raise ValueError("the collection returned no items; choose a collection with at least one Item")
    return features[0]


def main() -> int:
    args = parse_args()
    endpoint = f"{args.api_url.rstrip('/')}/collections/{args.collection}/items"
    full_response = requests.get(endpoint, params={"limit": 1}, timeout=10)
    full_feature = first_feature(full_response)

    fields = f"-{args.exclude_path}"
    filtered_response = requests.get(endpoint, params={"limit": 1, "fields": fields}, timeout=10)
    filtered_feature = first_feature(filtered_response)

    parent, field = args.exclude_path.split(".", maxsplit=1)
    if field in filtered_feature.get(parent, {}):
        raise AssertionError(f"{args.exclude_path} is still present in the filtered Item")

    print(f"Endpoint: {endpoint}")
    print(f"Excluded field: {args.exclude_path}")
    print(f"Full response: {len(full_response.content)} bytes")
    print(f"Filtered response: {len(filtered_response.content)} bytes")
    print(f"Item id: {full_feature.get('id')}")
    print("Fields demo passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (requests.RequestException, ValueError, AssertionError) as error:
        print(f"Fields demo failed: {error}", file=sys.stderr)
        raise SystemExit(1)
