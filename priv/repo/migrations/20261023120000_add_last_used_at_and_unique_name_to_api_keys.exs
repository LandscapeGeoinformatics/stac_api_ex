defmodule StacApi.Repo.Migrations.AddLastUsedAtAndUniqueNameToApiKeys do
  @moduledoc """
  Usability additions for personalized API keys.

  * `last_used_at` - when the key last authenticated a request, so stale keys
    can be spotted and deleted. Written at most once per hour per key (see
    `StacApi.Data.ApiKey.touch_last_used/1`), so it is approximate. NULL means
    the key has never been used.
  * unique index on `name` - keys are told apart by name in listings, so
    duplicates would be indistinguishable.

  If this fails on the unique index, two existing keys share a name: rename
  one via `PATCH /stac/manage/v1/api-keys/:id` and run the migration again.
  """
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add :last_used_at, :timestamptz
    end

    create unique_index(:api_keys, [:name])
  end
end
