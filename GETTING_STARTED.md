# Getting Started with STAC API

This is a Phoenix-based STAC (SpatioTemporal Asset Catalog) API implementation.

## Quick Start (Recommended)

### Option 1: Using the setup script

```bash
cd stac_api
./setup.sh
```

### Option 2: Manual setup

1. **Start PostGIS database:**

```bash
docker-compose up -d postgres
```

2. **Wait for database to be ready:**

```bash
docker-compose exec postgres pg_isready -U postgres -d stac_api_dev
```

3. **Install dependencies:**

```bash
mix deps.get
```

4. **Setup database:**

```bash
mix ecto.setup
```

5. **Import STAC data:**

```bash
mix stac.import
```

6. **Start the server:**

```bash
mix phx.server
```

## What's Included

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

- `est-topo-mtr/` - Estonian topographic data
- `world_clim/` - World climate data
- `hihydro_top_sub/` - Hydrological data
- `dcube_pub/` - Public data cube
- `C3S-LC-L4-LCCS-Map-300m-P1Y/` - Land cover data

## Development

- **Database**: PostgreSQL 15 with PostGIS 3.3
- **Framework**: Phoenix 1.7
- **Language**: Elixir 1.15+
- **Port**: 4000

## Troubleshooting

- Make sure Docker is running
- Check database connection: `docker-compose logs postgres`
- Reset database: `mix ecto.reset`
- Reimport data: `mix stac.import`
