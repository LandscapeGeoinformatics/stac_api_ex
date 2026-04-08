# STAC API Project Documentation

## Table of Contents

1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [Data Hierarchy](#data-hierarchy)
4. [API Endpoints](#api-endpoints)
5. [Authentication System](#authentication-system)
6. [Database Schema](#database-schema)
7. [Setup and Configuration](#setup-and-configuration)
8. [Flow Diagrams](#flow-diagrams)
9. [API Usage Examples](#api-usage-examples)

---

## Project Overview

This is a **Phoenix-based STAC (SpatioTemporal Asset Catalog) API** implementation that provides a comprehensive RESTful API for managing geospatial data catalogs. The system supports hierarchical organization of catalogs, collections, and items with full CRUD (Create, Read, Update, Delete) operations.

### Key Features

- **Hierarchical Catalog Structure**: Support for nested catalogs (up to 2 levels deep)
- **Full CRUD Operations**: Create, read, update, and delete catalogs, collections, and items
- **Authentication**: Two-tier authentication system (read-only and read-write)
- **Private/Public Catalogs**: Support for private catalogs that require authentication
- **PostGIS Integration**: Spatial data storage and querying using PostgreSQL with PostGIS
- **STAC Compliance**: Follows STAC 1.0.0 specification
- **Web Interface**: HTML browser interface for exploring STAC data
- **Cascade Deletes**: Automatic deletion of child resources when parent is deleted

---

## System Architecture

### Technology Stack

- **Framework**: Phoenix 1.7 (Elixir web framework)
- **Language**: Elixir 1.15+
- **Database**: PostgreSQL 15 with PostGIS 3.3
- **Spatial Library**: Geo.ex and GeoPostGIS
- **Server**: Bandit (HTTP/1.1 and HTTP/2 server)
- **JSON Library**: Jason

### Application Structure

```
StacApi/
├── Data/                    # Data layer (Ecto schemas)
│   ├── Catalog.ex          # Catalog schema
│   ├── Collection.ex       # Collection schema
│   ├── Item.ex             # Item schema
│   ├── ItemAsset.ex        # Item assets schema
│   └── Search.ex           # Search functionality
│
├── Web/                     # Web layer
│   ├── Controllers/        # Request handlers
│   │   ├── RootController.ex          # STAC API root, conformance, catalog browse
│   │   ├── SearchController.ex        # STAC search
│   │   ├── CollectionsController.ex   # STAC-conformant collection/item reads
│   │   ├── CatalogsCrudController.ex  # Management: catalog CRUD
│   │   ├── CollectionsCrudController.ex # Management: collection CRUD
│   │   ├── ItemsCrudController.ex     # Management: item CRUD + bulk import
│   │   └── StacBrowserController.ex   # Web GUI
│   ├── Plugs/              # Middleware
│   │   ├── AuthPlug.ex     # Write authentication
│   │   └── ReadAuthPlug.ex # Read authentication
│   └── Router.ex           # Route definitions
│
└── Repo.ex                  # Database repository
```

---

## Data Hierarchy

The STAC API follows a hierarchical structure where data is organized in three main levels:

### Hierarchy Levels

```
Catalog (Root Level)
  ├── Child Catalog (Nested, max 2 levels)
  │   └── Collection
  │       └── Item
  │           └── Item Asset
  │
  └── Collection (Direct)
      └── Item
          └── Item Asset
```

### Entity Descriptions

1. **Catalog**

   - Top-level organizational unit
   - Can contain child catalogs (nested hierarchy, max depth: 2 levels)
   - Can contain collections directly
   - Has a `private` flag for access control
   - Supports hierarchical relationships via `parent_catalog_id`

2. **Collection**

   - Groups related items together
   - Must belong to a catalog (or can be root-level if `catalog_id` is null)
   - Contains metadata about the collection (extent, license, summaries)
   - Links to multiple items

3. **Item**

   - Individual geospatial data assets
   - Must belong to a collection
   - Contains geometry (PostGIS Geography type)
   - Has temporal information (datetime)
   - Contains properties and assets

4. **Item Asset**
   - Actual data files/resources linked to items
   - Stored separately to support multiple assets per item
   - Contains metadata like scale, offset, projection shape

### Hierarchy Rules

- **Catalog Depth**: Maximum 2 levels of nested catalogs (root + 1 child level)
- **Cascade Deletes**: Deleting a catalog deletes all child catalogs, collections, and items
- **Required Relationships**: Items must belong to a collection; Collections should belong to a catalog (optional)

---

## API Endpoints

The API is split into two namespaces: the public STAC API (`/stac/api/v1`) and the internal Management API (`/stac/manage/v1`).

### 1. STAC API — Public Read (`/stac/api/v1`)

These endpoints are publicly accessible and STAC-conformant. They respect private catalog filtering: unauthenticated requests only see public content; providing a valid `X-API-Key` (RO or RW) unlocks private catalogs.

#### Root & Discovery

- `GET /stac/api/v1/` - Root catalog landing page with `conformsTo`
- `GET /stac/api/v1/conformance` - OGC/STAC conformance classes
- `GET /stac/api/v1/openapi.json` - OpenAPI specification
- `GET /stac/api/v1/docs` - API documentation
- `GET /stac/api/v1/catalog/:id` - Get specific catalog (non-standard, used by web GUI)

#### Search

- `GET /stac/api/v1/search` - Search STAC items (GET)
- `POST /stac/api/v1/search` - Search STAC items (POST with complex queries)

#### Collections & Items (STAC-conformant)

- `GET /stac/api/v1/collections` - List all collections
- `GET /stac/api/v1/collections/:id` - Get specific collection
- `GET /stac/api/v1/collections/:id/items` - Get items in a collection (paginated)
- `GET /stac/api/v1/collections/:collection_id/items/:item_id` - Get specific item

### 2. Management API — Requires Authentication (`/stac/manage/v1`)

All endpoints under this namespace require the `X-API-Key` header with a **read-write key**. These endpoints are not STAC-conformant and are intended for internal data management only.

#### Catalogs (Full CRUD)

- `GET /stac/manage/v1/catalogs` - List all catalogs
- `GET /stac/manage/v1/catalogs/:id` - Get specific catalog
- `POST /stac/manage/v1/catalogs` - Create a new catalog
- `PUT /stac/manage/v1/catalogs/:id` - Full replacement of a catalog
- `PATCH /stac/manage/v1/catalogs/:id` - Partial update of a catalog
- `DELETE /stac/manage/v1/catalogs/:id` - Delete catalog (cascade delete)

#### Collections (Full CRUD)

- `GET /stac/manage/v1/collections` - List all collections
- `GET /stac/manage/v1/collections/:id` - Get specific collection
- `POST /stac/manage/v1/collections` - Create a new collection
- `PUT /stac/manage/v1/collections/:id` - Full replacement of a collection
- `PATCH /stac/manage/v1/collections/:id` - Partial update of a collection
- `DELETE /stac/manage/v1/collections/:id` - Delete collection (cascade delete)

#### Items (Full CRUD)

- `GET /stac/manage/v1/items` - List all items
- `GET /stac/manage/v1/items/:id` - Get specific item
- `POST /stac/manage/v1/items` - Create a new item
- `POST /stac/manage/v1/items/import` - Bulk import items (GeoJSON FeatureCollection)
- `PUT /stac/manage/v1/items/:id` - Full replacement of an item
- `PATCH /stac/manage/v1/items/:id` - Partial update of an item
- `DELETE /stac/manage/v1/items/:id` - Delete an item

### 3. Web Interface Endpoints

- `GET /stac/web/browse` - HTML directory browser
- `GET /stac/web/browse/*path` - Browse specific paths
- `GET /stac/web/search` - HTML search interface
- `GET /stac/web/search/api` - JSON search API for AJAX calls

---

## Authentication System

The API implements a two-tier authentication system using API keys.

### Authentication Levels

1. **Read-Only Access** (`read_only`)

   - Can read all public catalogs
   - Can read private catalogs (when authenticated with read-only key)
   - Cannot perform write operations

2. **Read-Write Access** (`read_write`)
   - All read permissions
   - Can create, update, and delete resources
   - Required for all POST, PUT, PATCH, DELETE operations

### Authentication Mechanism

#### API Key Configuration

API keys are configured in the application config and can be set via environment variables:

**Development (default values):**

- Read-Write Key: `dev-api-key-2024`
- Read-Only Key: `dev-read-only-key-2024`

**Environment Variables:**

- `STAC_API_KEY` - Sets the read-write API key
- `STAC_API_KEY_RO` - Sets the read-only API key

#### Request Headers

All authenticated requests must include:

```
X-API-Key: your-api-key-here
```

#### Authentication Plugins

1. **ReadAuthPlug** (`StacApiWeb.Plugs.ReadAuthPlug`)

   - Used for read endpoints
   - Optional authentication (doesn't block requests)
   - Sets `:auth_level` and `:authenticated` in connection assigns
   - Used to filter private catalogs

2. **AuthPlug** (`StacApiWeb.Plugs.AuthPlug`)
   - Used for write endpoints
   - Required authentication (blocks requests without valid key)
   - Only accepts read-write keys
   - Returns 401 Unauthorized if authentication fails

### Private Catalogs

- Catalogs can be marked as `private: true`
- Private catalogs are only visible when:
  - An authenticated user (read-only or read-write) makes the request
  - The request includes a valid API key
- Unauthenticated requests only see public catalogs

---

## Database Schema

### Tables

#### catalogs

```sql
- id (string, primary key)
- title (string)
- description (string)
- type (string, default: "Catalog")
- stac_version (string, default: "1.0.0")
- extent (jsonb)
- links (jsonb array)
- depth (integer, default: 0)
- private (boolean, default: false)
- parent_catalog_id (string, foreign key to catalogs.id)
- inserted_at (timestamp)
- updated_at (timestamp)
```

#### collections

```sql
- id (string, primary key)
- title (string)
- description (string)
- license (string)
- extent (jsonb)
- summaries (jsonb)
- properties (jsonb)
- stac_version (string)
- stac_extensions (string array)
- links (jsonb array)
- catalog_id (string, foreign key to catalogs.id, nullable)
- inserted_at (timestamp)
- updated_at (timestamp)
```

#### items

```sql
- id (string, primary key)
- stac_version (string)
- stac_extensions (string array)
- geometry (geography, PostGIS)
- bbox (float array)
- datetime (timestamp)
- properties (jsonb)
- assets (jsonb)
- links (jsonb array)
- collection_id (string, foreign key to collections.id)
- inserted_at (timestamp)
- updated_at (timestamp)
```

#### item_assets

```sql
- id (integer, primary key, auto-increment)
- item_id (string, foreign key to items.id)
- href (string)
- title (string)
- description (string)
- type (string)
- roles (string array)
- scale (float)
- offset (float)
- proj_shape (integer array)
- inserted_at (timestamp)
- updated_at (timestamp)
```

### Relationships

- Catalog → Catalog (self-referential, `parent_catalog_id`)
- Catalog → Collections (`catalog_id` in collections)
- Collection → Items (`collection_id` in items)
- Item → Item Assets (`item_id` in item_assets)

### Cascade Delete Rules

- Deleting a **Catalog** deletes:

  - All child catalogs
  - All collections in the catalog
  - All items in those collections
  - All item assets for those items

- Deleting a **Collection** deletes:

  - All items in the collection
  - All item assets for those items

- Deleting an **Item** deletes:
  - All item assets for that item

---

## Setup and Configuration

### Prerequisites

- Elixir 1.15+
- PostgreSQL 15 with PostGIS 3.3
- Docker (for running PostGIS database)
- Mix (Elixir build tool)

### Installation Steps

1. **Start PostGIS Database**

   ```bash
   docker-compose up -d postgres
   ```

2. **Wait for Database to be Ready**

   ```bash
   docker-compose exec postgres pg_isready -U postgres -d stac_api_dev
   ```

3. **Install Dependencies**

   ```bash
   mix deps.get
   ```

4. **Create Database**

   ```bash
   mix ecto.create
   ```

5. **Run Migrations**

   ```bash
   mix ecto.migrate
   ```

6. **Import STAC Data (Optional)**

   ```bash
   mix stac.import
   ```

7. **Start the Server**
   ```bash
   mix phx.server
   ```

The server will be available at `http://localhost:4000`

### Configuration

#### Database Configuration

Located in `config/dev.exs`:

- Host: `localhost`
- Port: `5433` (or `DB_PORT` environment variable)
- Database: `stac_api_dev`
- User: `postgres`
- Password: `postgres`

#### API Keys Configuration

Located in `config/dev.exs`:

- Default read-write key: `dev-api-key-2024`
- Default read-only key: `dev-read-only-key-2024`
- Can be overridden with environment variables `STAC_API_KEY` and `STAC_API_KEY_RO`

---

## Flow Diagrams

### 1. Request Flow Through Authentication

```
┌─────────────┐
│   Client    │
│  Request    │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Router            │
│   (Route Match)     │
└──────┬──────────────┘
       │
       ├─────────────────┬─────────────────┐
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐  ┌──────────────┐  ┌─────────────┐
│ Browser     │  │ Read Auth    │  │ Write Auth  │
│ Pipeline    │  │ Pipeline     │  │ Pipeline    │
│ (HTML)      │  │ (Optional)   │  │ (Required)  │
└──────┬──────┘  └──────┬───────┘  └──────┬──────┘
       │                 │                 │
       │                 ▼                 ▼
       │          ┌──────────────┐  ┌──────────────┐
       │          │ ReadAuthPlug │  │  AuthPlug    │
       │          │ - Check key  │  │ - Check key  │
       │          │ - Set auth   │  │ - Require RW │
       │          │ - Continue   │  │ - Block if   │
       │          │   even if    │  │   invalid    │
       │          │   missing    │  │              │
       │          └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       └─────────────────┴─────────────────┘
                         │
                         ▼
                 ┌───────────────┐
                 │   Controller  │
                 │   (Business   │
                 │    Logic)     │
                 └───────┬───────┘
                         │
                         ▼
                 ┌───────────────┐
                 │   Repository  │
                 │   (Database   │
                 │    Access)    │
                 └───────┬───────┘
                         │
                         ▼
                 ┌───────────────┐
                 │   Response    │
                 │   (JSON/HTML) │
                 └───────────────┘
```

### 2. Data Hierarchy Flow

```
                    ┌──────────────┐
                    │   Catalog    │
                    │  (Root)      │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   Catalog    │  │  Collection  │  │  Collection  │
    │  (Child)     │  │  (Direct)    │  │  (Direct)    │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │  Collection  │  │     Item     │  │     Item     │
    │  (Nested)    │  └──────┬───────┘  └──────┬───────┘
    └──────┬───────┘         │                 │
           │                 ▼                 ▼
           ▼          ┌──────────────┐  ┌──────────────┐
    ┌──────────────┐  │ Item Asset   │  │ Item Asset   │
    │     Item     │  └──────────────┘  └──────────────┘
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │ Item Asset   │
    └──────────────┘
```

### 3. CRUD Operation Flow (Create Catalog)

```
┌─────────────┐
│   Client    │
│  POST /stac/│
│  manage/v1/ │
│  catalogs   │
│  + Body     │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Router            │
│   Match Route       │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   AuthPlug          │
│   - Check X-API-Key │
│   - Validate RW key │
└──────┬──────────────┘
       │
       ▼ (if valid)
┌─────────────────────┐
│ CatalogsCrud        │
│ Controller.create   │
│ - Validate params   │
│ - Build changeset   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Catalog Schema    │
│   changeset/2       │
│   - Validate data   │
│   - Check rules     │
└──────┬──────────────┘
       │
       ▼ (if valid)
┌─────────────────────┐
│   Repository        │
│   Repo.insert       │
│   - Insert to DB    │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Response          │
│   201 Created       │
│   + Catalog JSON    │
└─────────────────────┘
```

### 4. Cascade Delete Flow

```
┌─────────────┐
│   Client    │
│  DELETE     │
│  /manage/v1/│
│  catalogs/  │
│  :id        │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   AuthPlug          │
│   (Authenticate)    │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ CatalogsCrud        │
│ Controller.delete   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Repository        │
│   Multi Transaction │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────────┐
│   1. Find Catalog               │
│   2. Find Child Catalogs        │
│   3. Find Collections           │
│   4. Find Items                 │
│   5. Find Item Assets           │
│   6. Delete in reverse order:   │
│      - Item Assets              │
│      - Items                    │
│      - Collections              │
│      - Child Catalogs           │
│      - Root Catalog             │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────┐
│   Response          │
│   204 No Content    │
└─────────────────────┘
```

### 5. Search Flow with Private Catalog Filtering

```
┌─────────────┐
│   Client    │
│  GET/POST   │
│  /search    │
│  + Query    │
│  + X-API-Key│
│    (optional)│
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   ReadAuthPlug      │
│   - Check key       │
│   - Set auth_level  │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ SearchController    │
│ - Parse query       │
│ - Build search      │
│   parameters        │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Search Module     │
│   - Apply filters   │
│   - Check auth      │
│   - Filter private  │
│     catalogs        │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Repository        │
│   - Query items     │
│   - Apply spatial   │
│     filters         │
│   - Paginate        │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   Response          │
│   200 OK            │
│   + FeatureCollection│
│     (filtered items)│
└─────────────────────┘
```

---

## API Usage Examples

### 1. Create a Root Catalog

**Request:**

```http
POST /stac/manage/v1/catalogs
Content-Type: application/json
X-API-Key: dev-api-key-2024

{
  "id": "satellite-imagery",
  "title": "Satellite Imagery Catalog",
  "description": "Collection of satellite imagery datasets",
  "type": "Catalog",
  "stac_version": "1.0.0",
  "links": [
    {
      "rel": "license",
      "href": "https://creativecommons.org/licenses/by/4.0/",
      "title": "CC BY 4.0"
    }
  ]
}
```

**Response:**

```json
{
  "id": "satellite-imagery",
  "title": "Satellite Imagery Catalog",
  "description": "Collection of satellite imagery datasets",
  "type": "Catalog",
  "stac_version": "1.0.0",
  "links": [...],
  "depth": 0,
  "private": false
}
```

### 2. Create a Nested Catalog

**Request:**

```http
POST /stac/manage/v1/catalogs
Content-Type: application/json
X-API-Key: dev-api-key-2024

{
  "id": "sentinel-catalog",
  "title": "Sentinel Satellite Catalog",
  "description": "Nested catalog for Sentinel satellite data",
  "type": "Catalog",
  "stac_version": "1.0.0",
  "parent_catalog_id": "satellite-imagery"
}
```

### 3. Create a Collection

**Request:**

```http
POST /stac/manage/v1/collections
Content-Type: application/json
X-API-Key: dev-api-key-2024

{
  "id": "sentinel-2-l2a",
  "title": "Sentinel-2 Level-2A",
  "description": "Sentinel-2 Level-2A surface reflectance products",
  "license": "CC-BY-4.0",
  "catalog_id": "satellite-imagery",
  "stac_version": "1.0.0",
  "extent": {
    "spatial": {
      "bbox": [[-180, -90, 180, 90]]
    },
    "temporal": {
      "interval": [["2015-06-23T00:00:00Z", "2024-12-31T23:59:59Z"]]
    }
  }
}
```

### 4. Create an Item

**Request:**

```http
POST /stac/manage/v1/items
Content-Type: application/json
X-API-Key: dev-api-key-2024

{
  "id": "sentinel-2-l2a-20240101",
  "stac_version": "1.0.0",
  "collection_id": "sentinel-2-l2a",
  "geometry": {
    "type": "Polygon",
    "coordinates": [[
      [0, 0],
      [1, 0],
      [1, 1],
      [0, 1],
      [0, 0]
    ]]
  },
  "bbox": [0, 0, 1, 1],
  "datetime": "2024-01-01T00:00:00Z",
  "properties": {
    "eo:cloud_cover": 5.2
  },
  "assets": {
    "B04": {
      "href": "https://example.com/data/B04.tif",
      "type": "image/tiff; application=geotiff",
      "title": "Red band"
    }
  }
}
```

### 5. Search Items (Public, No Auth)

**Request:**

```http
GET /stac/api/v1/search?bbox=0,0,1,1&datetime=2024-01-01T00:00:00Z/2024-12-31T23:59:59Z
```

**Response:**

```json
{
  "type": "FeatureCollection",
  "features": [...],
  "links": [...]
}
```

### 6. Search Items (With Auth for Private Catalogs)

**Request:**

```http
GET /stac/api/v1/search?bbox=0,0,1,1
X-API-Key: dev-read-only-key-2024
```

### 7. Update Catalog (Partial)

**Request:**

```http
PATCH /stac/manage/v1/catalogs/satellite-imagery
Content-Type: application/json
X-API-Key: dev-api-key-2024

{
  "title": "Updated Satellite Imagery Catalog",
  "private": true
}
```

### 8. Delete Catalog (Cascade)

**Request:**

```http
DELETE /stac/manage/v1/catalogs/satellite-imagery
X-API-Key: dev-api-key-2024
```

**Note:** This will delete the catalog and ALL child catalogs, collections, items, and item assets.

---

## Summary

This STAC API implementation provides:

1. **Hierarchical Organization**: Catalogs can contain child catalogs and collections, supporting complex organizational structures

2. **Full CRUD Operations**: Complete create, read, update, and delete functionality for all resources

3. **Security**: Two-tier authentication system with public read access and protected write access

4. **Private Catalogs**: Support for private catalogs that require authentication to view

5. **Cascade Deletes**: Automatic cleanup of child resources when parents are deleted

6. **STAC Compliance**: Follows STAC 1.0.0 specification for interoperability

7. **Spatial Support**: PostGIS integration for spatial queries and geometry storage

8. **Web Interface**: HTML browser interface for exploring and browsing STAC data

The system is designed to be scalable, maintainable, and compliant with STAC standards while providing additional features like hierarchical catalogs and comprehensive CRUD operations.
