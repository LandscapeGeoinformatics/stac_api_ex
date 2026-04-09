# Getting Started with STAC API

This is a Phoenix-based STAC (SpatioTemporal Asset Catalog) API implementation.

## Quick Start (Recommended)

1. **Install dependencies:**

```bash
mix deps.get
```

2. **Setup database:**

```bash
mix ecto.setup
```

3. **Start the server:**

```bash
mix phx.server
```

## What's needed

- **PostGIS Database**: Spatial database with PostGIS extension
- **STAC Data**: Sample collections and items already included
- **API Endpoints**: RESTful STAC API endpoints
- **Browser Interface**: HTML interface for browsing STAC data

## API Endpoints

### STAC API — public read (optional auth unlocks private catalogs)

- `GET /stac/api/v1/` - Root catalog landing page
- `GET /stac/api/v1/conformance` - OGC/STAC conformance classes
- `GET /stac/api/v1/search` - Search STAC items (GET)
- `POST /stac/api/v1/search` - Search STAC items (POST with body)
- `GET /stac/api/v1/collections` - List all collections
- `GET /stac/api/v1/collections/:id` - Get specific collection
- `GET /stac/api/v1/collections/:id/items` - Get items in collection
- `GET /stac/api/v1/collections/:collection_id/items/:item_id` - Get specific item
- `GET /stac/api/v1/openapi.json` - OpenAPI specification
- `GET /stac/api/v1/docs` - API documentation

### Management API — requires `X-API-Key` (read-write key)

- `GET  /stac/manage/v1/catalogs` - List all catalogs
- `GET  /stac/manage/v1/catalogs/:id` - Get specific catalog
- `POST /stac/manage/v1/catalogs` - Create catalog
- `PUT  /stac/manage/v1/catalogs/:id` - Replace catalog
- `PATCH /stac/manage/v1/catalogs/:id` - Partial update catalog
- `DELETE /stac/manage/v1/catalogs/:id` - Delete catalog (cascade)
- `GET  /stac/manage/v1/collections` - List all collections (CRUD view)
- `POST /stac/manage/v1/collections` - Create collection
- `PUT  /stac/manage/v1/collections/:id` - Replace collection
- `PATCH /stac/manage/v1/collections/:id` - Partial update collection
- `DELETE /stac/manage/v1/collections/:id` - Delete collection (cascade)
- `GET  /stac/manage/v1/items` - List all items (CRUD view)
- `POST /stac/manage/v1/items` - Create item
- `POST /stac/manage/v1/items/import` - Bulk import items
- `PUT  /stac/manage/v1/items/:id` - Replace item
- `PATCH /stac/manage/v1/items/:id` - Partial update item
- `DELETE /stac/manage/v1/items/:id` - Delete item

### Web browser interface

- `GET /stac/web/browse` - HTML browser interface

## STAC Data Structure

The application includes sample STAC data:

- `misc/testdata/` - Sentinel 2 NDVI over Estonia

## Development

- **Database**: PostgreSQL 15 with PostGIS 3.3
- **Framework**: Phoenix 1.7
- **Language**: Elixir 1.15+
- **Port**: 4000

## Python CLI Tool (`misc/test_stac_api.py`)

A Python script in `misc/` provides a command-line interface for interacting with
both the STAC read API and the Management API.  It can be used as a demo test
suite or as a composable tool for day-to-day data management tasks.

### Prerequisites

```bash
cd misc
pixi install          # installs requests, pystac, pystac-client via pixi.toml
```

Or with pip:

```bash
pip install requests pystac pystac-client
```

### Usage

```bash
cd misc
python test_stac_api.py [GLOBAL OPTIONS] COMMAND [COMMAND OPTIONS]
```

Global options must be placed **before** the command name:

| Option | Default | Description |
|---|---|---|
| `--api-url URL` | `http://localhost:4000/stac/api/v1` | STAC read API base URL |
| `--manage-url URL` | `http://localhost:4000/stac/manage/v1` | Management API base URL |
| `--rw-key KEY` | `dev-api-key-2024` | Read-write API key |
| `--ro-key KEY` | `dev-read-only-key-2024` | Read-only API key |
| `--testdata DIR` | `misc/testdata/demo_2017` | Path to demo testdata directory |

### Bulk demo commands

These commands are self-contained demos that use the bundled testdata:

| Command | Description |
|---|---|
| `insert` | Create the public catalog hierarchy (`geokuup` → `estonia`) + NDVI collection + 3 seasonal items |
| `query` | Run pystac-client searches (GET + POST, bbox, temporal, item ID, asset inspection) |
| `delete` | Cascade-delete the `geokuup` catalog (removes `estonia`, the collection, and all items) |
| `private-demo` | Create public/private catalogs, validate visibility rules (with/without API key), then clean up |
| `all` | Run `insert` → `query` → `delete` → `private-demo` in sequence |

```bash
cd misc
python test_stac_api.py all                # full demo run
python test_stac_api.py insert             # seed demo data only
python test_stac_api.py query              # run searches against seeded data
python test_stac_api.py delete             # tear down demo data
python test_stac_api.py private-demo       # access-control demonstration
```

### Composable single-resource commands

These commands operate on individual resources and accept file or ID arguments.
All update commands use HTTP PATCH — only fields present in the supplied file
are changed on the server; absent fields are left untouched.

**Create**

```bash
python test_stac_api.py create-catalog    --file cat.json
python test_stac_api.py create-catalog    --file cat.json --catalog-id my-id

python test_stac_api.py create-collection --file col.json
python test_stac_api.py create-collection --file col.json --catalog-id geokuup

python test_stac_api.py add-item          --file item.json --collection-id my-collection
```

**Update (PATCH)**

```bash
python test_stac_api.py update-catalog    --file cat.json
python test_stac_api.py update-catalog    --file cat.json  --catalog-id geokuup

python test_stac_api.py update-collection --file col.json
python test_stac_api.py update-collection --file col.json  --collection-id estonia-sentinel2-ndvi
python test_stac_api.py update-collection --file col.json  --catalog-id geokuup     # move to catalog
python test_stac_api.py update-collection --file col.json  --catalog-id ""          # detach from catalog

python test_stac_api.py update-item       --file item.json
python test_stac_api.py update-item       --file item.json --item-id my-item-id
python test_stac_api.py update-item       --file item.json --collection-id my-collection
```

> **Note on collection extent:** spatial and temporal extent are recomputed
> server-side on every item mutation.  Omit `extent` from collection update
> files to leave the server-managed value intact.

**Delete**

```bash
python test_stac_api.py delete-item       --item-id est_s2_ndvi_2017-04-01_2017-05-31
python test_stac_api.py delete-collection --collection-id estonia-sentinel2-ndvi
python test_stac_api.py delete-catalog    --catalog-id geokuup    # cascade: all children removed
```

### Override API keys or target URL

```bash
# Point at a staging server with a different key
python test_stac_api.py \
  --api-url    http://localhost:4000/stac/api/v1 \
  --manage-url http://localhost:4000/stac/manage/v1 \
  --rw-key     dev-api-key-2024 \
  insert 
# demo bulk setup
```
