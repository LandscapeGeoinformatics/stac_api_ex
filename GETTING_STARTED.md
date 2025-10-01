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

- `GET /` - Root catalog
- `GET /search` - Search STAC items
- `GET /collections` - List all collections
- `GET /collections/:id` - Get specific collection
- `GET /collections/:id/items` - Get items in collection
- `GET /stac/browse` - HTML browser interface

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
