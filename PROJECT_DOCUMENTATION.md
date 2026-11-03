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
- **Common Metadata Timestamps**: `created` / `updated` exposed as RFC 3339 on the Management API, enabling write-conflict detection for syncing clients
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
├── Schema.ex                # Shared Ecto schema base (timestamp type)
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
│   │   ├── StacBrowserController.ex   # Web GUI
│   │   ├── CatalogJSON.ex             # Management: catalog serializer
│   │   ├── CollectionJSON.ex          # Management: collection serializer
│   │   ├── ItemJSON.ex                # Management: item serializer
│   │   └── STACDateTime.ex            # RFC 3339 timestamp rendering
│   ├── Plugs/              # Middleware
│   │   ├── AuthPlug.ex     # Write authentication
│   │   └── ReadAuthPlug.ex # Read authentication
│   └── Router.ex           # Route definitions
│
└── Repo.ex                  # Database repository
```

### Response Serialization

The Management API builds its responses through one serializer module per type, so each
STAC representation is defined exactly once rather than being rebuilt inline in every
controller action:

| Module | Entry point | Used by |
|---|---|---|
| `StacApiWeb.CatalogJSON` | `to_stac/2` | `CatalogsCrudController` (create/show/update/patch/index) |
| `StacApiWeb.CollectionJSON` | `to_stac/3` | `CollectionsCrudController` (create/show/update/patch/index) |
| `StacApiWeb.ItemJSON` | `to_stac/3` | `ItemsCrudController` (create/show/update/patch/index) |

Links and assets are passed in by the caller rather than computed inside the serializer:
the link set varies per request (custom links from the request body on writes, persisted
links on reads) and assets require a database round-trip.

`CollectionJSON.to_stac/3` accepts `drop_nils: true`, which the read actions pass. This
preserves a long-standing difference in the Management API: `GET` omits nil-valued fields
while `POST` / `PUT` / `PATCH` return them as `null`.

The **public** STAC API does not use these modules — it has its own representations in
`CollectionsController.sanitize_collection/1` and `StacApi.Data.Search.serialize_item_for_api/1`.

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

#### API Keys (personal read-only keys)

- `GET /stac/manage/v1/api-keys` - List keys (never includes secrets)
- `GET /stac/manage/v1/api-keys/:id` - Get a specific key
- `POST /stac/manage/v1/api-keys` - Create a key from a `name`; the secret is returned once, under `data.key`
- `PATCH /stac/manage/v1/api-keys/:id` - Rename a key (the secret is unchanged)
- `POST /stac/manage/v1/api-keys/:id/rotate` - Issue a new secret; the old one stops working immediately
- `DELETE /stac/manage/v1/api-keys/:id` - Permanently delete a key

Fields returned for a key: `id`, `name`, `key_prefix`, `last_used_at`, `inserted_at`,
`updated_at`, and `key` (create and rotate only). See
[Personalized read-only keys](#personalized-read-only-keys) for how they authenticate.

Errors: `404` for an unknown or non-numeric id; `422` with `{"error": "Validation failed",
"details": {"name": [...]}}` for a blank, over-long (more than 100 characters) or duplicate
name. Names are trimmed.

#### Management API Response Fields

Beyond the STAC fields, Management API responses carry:

| Field | Where | Notes |
|---|---|---|
| `created` / `updated` | Catalogs, collections: top level. Items: inside `properties` | RFC 3339 UTC with microseconds (`2026-08-05T21:48:19.248683Z`), from `inserted_at` / `updated_at`. Placement follows STAC Common Metadata. |
| `catalog_id` | Collections | The owning catalog, or `null` for root-level collections. Not a STAC field — the `parent` link deliberately points at the STAC root for every collection, since catalogs have no conformant route, so this is the only way to see the relationship. |

Two behaviours to be aware of when consuming these:

- **Server timestamps win.** Any `created` / `updated` a client sends in an item's
  `properties` is replaced by the server's own values on the way out. A client that got its
  own value echoed back could not detect that the server had been written to meanwhile,
  which is the point of exposing them.
- **`GET` omits nil fields.** Collection reads drop nil-valued fields, so a root-level
  collection has no `catalog_id` key at all, while writes return it as `null`.

`created` / `updated` are microsecond-precision, so `updated` can be compared before a
`PATCH` to detect that a resource changed server-side since it was read.

---

## STAC Datetime Handling

STAC follows RFC 3339 §5.6 and requires UTC. The API enforces this rather than coercing:
a value it cannot read is a `400`, never a silently stored `NULL`.

### Writing items

An item's temporal information is read from `properties` only. **There is no top-level
`datetime` field** — that shape predates STAC 1.0.0 and is not accepted.

```jsonc
// an instant
"properties": { "datetime": "2024-05-01T18:27:48Z" }

// a range — datetime MUST be null, and both bounds are then mandatory
"properties": {
  "datetime": null,
  "start_datetime": "2024-05-01T18:27:00Z",
  "end_datetime":   "2024-05-01T18:28:30Z"
}
```

Rules enforced on `POST`, `PUT`, `PATCH` and bulk import:

| Rule | Violation |
|---|---|
| Every value carries a UTC offset (`Z` or `+03:00`) | `400` — `properties.datetime must carry a UTC offset…` |
| `datetime` non-null, **or** both `start_datetime` and `end_datetime` present | `400` |
| `start_datetime` ≤ `end_datetime` | `400` |
| Value is a parseable date-time (not a bare date) | `400` |

Non-UTC offsets are accepted and **normalized**: `2024-05-01T21:27:48+03:00` is stored and
returned as `2024-05-01T18:27:48Z`. Because normalization happens at write time, every
endpoint renders the identical string, and the stored JSONB is always safe for SQL that
casts it. Sub-second precision is preserved.

`PATCH` replaces `properties` wholesale rather than merging, so a `PATCH` that supplies
`properties` must include the temporal fields — otherwise it would silently erase them,
and is rejected. A `PATCH` that does not supply `properties` at all leaves them untouched.

The parsed values populate the `datetime` / `start_datetime` / `end_datetime` columns,
which is what makes items findable by temporal search and what feeds collection extents.

### Searching

The `datetime` query parameter accepts an instant or an interval separated by `/`, with
`..` (or empty) for an open end:

```
datetime=2024-05-01T18:27:48Z
datetime=2024-01-01T00:00:00Z/2024-05-01T23:59:59Z
datetime=../2024-05-01T23:59:59Z
datetime=2024-01-01T00:00:00Z/..
```

Matching is by **intersection** with the item's temporal footprint — its `datetime` if it
has one, otherwise its `[start_datetime, end_datetime]` span. An instant therefore matches
a range item that contains it, and range items are reachable by temporal search at all.

Query parsing is deliberately more permissive than write parsing: a naive value is read as
UTC and a bare date as midnight UTC, which keeps the HTML browser's date picker
(`<input type="datetime-local">`, which emits `YYYY-MM-DDTHH:MM`) working. A wrong guess
costs one query's results rather than stored data. Genuinely unparseable input is still a
`400`, so a bad parameter never silently widens the query to the whole catalogue.

### Collection extents

`extent.spatial` and `extent.temporal` are always recomputed from the collection's own
items whenever an item is written; a client-supplied extent is not preserved. The temporal
extent spans `LEAST(datetime, start_datetime)` to `GREATEST(datetime, end_datetime)` over
the collection, using the typed columns. Open ends are emitted as JSON `null`, per the
Collection spec:

```json
"temporal": { "interval": [["2015-06-23T00:00:00Z", null]] }
```

### Existing data

Rows written before this was enforced have their temporal values only in `properties`,
leaving `datetime` / `start_datetime` / `end_datetime` empty — which means they are **not
findable by temporal search and contribute nothing to collection extents**. The backfill
populates those columns and canonicalizes the `properties` strings.

It parses leniently — rescuing data already stored rather than rejecting it — and reports
how many values needed that leniency, since those would now be refused on write.
Unparseable values are left untouched rather than aborting the run. It is idempotent, so a
second run over consistent data reports zero rows.

Development, via Mix:

```bash
mix stac.backfill_temporal --dry-run
mix stac.backfill_temporal
mix stac.backfill_temporal --batch-size 2000
```

Production runs as a release, which ships without Mix. Use the release entry point, which
takes the same switches as a list of strings and starts the repo itself:

```bash
bin/stac_api eval 'StacApi.Release.backfill_temporal(["--dry-run"])'
bin/stac_api eval 'StacApi.Release.backfill_temporal()'
bin/stac_api eval 'StacApi.Release.backfill_temporal(["--batch-size", "2000"])'
```

Both are thin wrappers over `StacApi.Data.TemporalBackfill.run/1`, so they do exactly the
same work.

#### Deployment order

1. `bin/stac_api eval 'StacApi.Release.migrate()'` — the `timestamptz(6)` conversion
   rewrites tables under an `ACCESS EXCLUSIVE` lock, so schedule a window for it.
2. Deploy the new release.
3. `bin/stac_api eval 'StacApi.Release.backfill_temporal(["--dry-run"])'`, then without
   `--dry-run`.

The order is forced: the columns must exist before the new code runs, and the backfill
uses the new schema. Step 3 takes no exclusive lock and the service stays up, but skipping
it fails **silently** — temporal search simply returns nothing for pre-existing items.

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

#### Personalized read-only keys

On top of the two static keys, read-write users can issue any number of named, read-only
keys through the API key endpoints (see [API Keys](#api-keys-personal-read-only-keys)).
They are meant for giving individual people or scripts their own key that can be
revoked or rotated on its own.

- **Access:** the same as the static read-only key. They unlock private catalogs through
  `ReadAuthPlug` and through the web browser unlock form. They are rejected by `AuthPlug`,
  so they can never write or manage keys.
- **Storage:** the `api_keys` table keeps only a SHA-256 hash of each key (`key_hash`),
  a short non-secret `key_prefix` for display, the `name`, and `last_used_at`. The raw
  key (`stac_ro_` followed by random characters) is shown once on creation or rotation
  and cannot be recovered; rotate to replace it.
- **Check order:** `ReadAuthPlug` tries the static read-write keys, then the static
  read-only keys, then looks the hash up in `api_keys`. Only a request with a key that
  matches none of the static keys costs a database query.
- **`last_used_at`:** refreshed on use by one conditional `UPDATE`, at most once an hour
  per key, so it is approximate.
- **Browser sessions:** the key is checked when the browse session is unlocked. A session
  that is already unlocked stays unlocked if its key is deleted later, until the session
  ends or the lock is used.

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
- inserted_at (timestamptz(6))
- updated_at (timestamptz(6))
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
- inserted_at (timestamptz(6))
- updated_at (timestamptz(6))
```

#### items

```sql
- id (string, primary key)
- stac_version (string)
- stac_extensions (string array)
- geometry (geography, PostGIS)
- bbox (float array)
- datetime (timestamptz(6), STAC observation instant; null for range items)
- start_datetime (timestamptz(6), indexed; set when the item describes a range)
- end_datetime (timestamptz(6), indexed; set when the item describes a range)
- properties (jsonb)
- assets (jsonb)
- links (jsonb array)
- collection_id (string, foreign key to collections.id)
- inserted_at (timestamptz(6))
- updated_at (timestamptz(6))
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
- created_at (timestamptz(6), asset creation time from STAC `created`)
- inserted_at (timestamptz(6))
- updated_at (timestamptz(6))
```

### Timestamps

All four tables carry `inserted_at` / `updated_at`; `items` additionally has the STAC
observation `datetime` and `item_assets` a `created_at`. All ten columns are
**`timestamptz(6)`** — time-zone aware, microsecond precision.

The Elixir-side type is declared **once**, in `StacApi.Schema`, which every schema module
`use`s in place of `use Ecto.Schema`:

```elixir
@timestamps_opts [type: :utc_datetime_usec]
```

Three things this arrangement buys, each of which was a real defect before:

1. **Valid RFC 3339 on the wire.** A `NaiveDateTime` renders as `2026-08-05T21:48:19` — no
   offset, not STAC-conformant, and nothing signals the problem. A UTC `DateTime` renders
   as `2026-08-05T21:48:19.248683Z`. Declaring the type centrally makes the correct
   rendering the default rather than something each serializer must remember.

2. **Timezone-independent comparisons.** `update_collection_extent/1` compares
   `items.datetime` against `timestamptz` values cast out of `properties`. While `datetime`
   was naive, Postgres resolved that mix using the **session** `TimeZone` — under a
   `Europe/Tallinn` session a single item at `10:00Z` produced the interval
   `[07:00Z, 10:00Z]`. Both sides are now `timestamptz`, so the comparison is between
   instants and no session setting can move it. Regression test:
   `"is unaffected by a non-UTC session TimeZone"` in `items_crud_controller_test.exs`.

3. **Microsecond precision for conflict detection.** At second precision, a client that
   reads and writes inside the same second cannot tell that the resource changed underneath
   it. The column precision and the Ecto type have to agree: declaring `_usec` over a
   `timestamp(0)` column just makes Postgres truncate on write and return a fake `.000000`.

Worth knowing when adding a schema or migration: Ecto's `:utc_datetime` /
`:utc_datetime_usec` map to Postgres `timestamp`, **not** `timestamptz`. Declaring the type
does not by itself give the column a time zone — the migration has to say `timestamptz`
explicitly. Use `StacApi.Schema` for new schemas so the type stays decided in one place.

#### Converting timestamp columns

Migration `20260806080000_convert_timestamps_to_timestamptz.exs` performed this conversion.
If you add a naive timestamp column later, convert it the same way:

```sql
ALTER TABLE items
  ALTER COLUMN inserted_at TYPE timestamptz(6) USING inserted_at AT TIME ZONE 'UTC';
```

The `USING ... AT TIME ZONE 'UTC'` clause is **not optional**. Postgres's implicit
`timestamp -> timestamptz` conversion interprets the naive value in the session `TimeZone`,
so without it the same migration silently produces different data depending on who runs it
and from where — verified on a scratch table, where a `Europe/Tallinn` session shifted the
value by three hours. Every value in these columns was written by Ecto as UTC, so stating
that explicitly is both correct and reproducible.

Note that changing a column's type rewrites the table under an `ACCESS EXCLUSIVE` lock:
reads and writes to that table block for the duration. Check table sizes and schedule a
window before running such a migration against production. The migration is transactional
and reversible; `down` converts back to `timestamp(0)`.

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
  "success": true,
  "message": "Catalog created successfully",
  "data": {
    "id": "satellite-imagery",
    "title": "Satellite Imagery Catalog",
    "description": "Collection of satellite imagery datasets",
    "type": "Catalog",
    "stac_version": "1.0.0",
    "extent": null,
    "created": "2026-08-05T21:48:19.248683Z",
    "updated": "2026-08-05T21:48:19.248683Z",
    "links": [...]
  }
}
```

Write operations (`POST`, `PUT`, `PATCH`, `DELETE`) wrap the resource in a
`success` / `message` / `data` envelope; `GET` returns the resource directly.

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

**Response** (`data`, envelope omitted):

```json
{
  "id": "sentinel-2-l2a",
  "type": "Collection",
  "title": "Sentinel-2 Level-2A",
  "license": "CC-BY-4.0",
  "catalog_id": "satellite-imagery",
  "stac_version": "1.0.0",
  "stac_extensions": [],
  "extent": {...},
  "created": "2026-08-05T21:48:19.248683Z",
  "updated": "2026-08-05T21:48:19.248683Z",
  "links": [...]
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
  "properties": {
    "datetime": "2024-01-01T00:00:00Z",
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

**Response** (`data`, envelope omitted) — note `created` / `updated` sit inside
`properties` for items, unlike catalogs and collections:

```json
{
  "id": "sentinel-2-l2a-20240101",
  "type": "Feature",
  "collection": "sentinel-2-l2a",
  "stac_version": "1.0.0",
  "geometry": {...},
  "bbox": [0, 0, 1, 1],
  "properties": {
    "eo:cloud_cover": 5.2,
    "created": "2026-08-05T21:48:19.248683Z",
    "updated": "2026-08-05T21:48:19.248683Z"
  },
  "assets": {...},
  "links": [...]
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
