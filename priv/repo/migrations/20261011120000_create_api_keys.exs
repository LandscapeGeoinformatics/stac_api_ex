defmodule StacApi.Repo.Migrations.CreateApiKeys do
  @moduledoc """
  Table for personalized, read-only API keys issued and managed through
  /stac/manage/v1/api-keys, independent of the single static RW/RO keys
  configured via STAC_API_KEY / STAC_API_KEY_RO.

  Only `key_hash` (SHA-256 of the raw secret) is stored. The raw secret is
  shown once at creation/rotation and is never persisted, matching how
  GitHub/Stripe-style API tokens are handled. `key_prefix` is a short,
  non-secret slice of the raw secret kept only so `GET /api-keys` can show
  which key is which without ever re-exposing the secret.

  `last_used_at` records when the key last authenticated a request, so stale
  keys can be spotted and deleted. It is written at most once per hour per key
  (see `StacApi.Data.ApiKey.touch_last_used/1`), so it is approximate. NULL
  means the key has never been used.

  `name` is unique because keys are told apart by name in listings, so
  duplicates would be indistinguishable.

  Uses `timestamptz` directly (not `timestamps()`'s default) per the lesson
  in StacApi.Schema and the 20260806080000 migration: `:utc_datetime_usec`
  needs a `timestamptz` column to round-trip correctly.
  """
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :name, :string, null: false
      add :key_hash, :string, null: false
      add :key_prefix, :string, null: false
      add :last_used_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:api_keys, [:key_hash])
    create unique_index(:api_keys, [:name])
  end
end
