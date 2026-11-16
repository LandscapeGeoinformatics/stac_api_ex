defmodule StacApi.Repo.Migrations.AddRoleExpiryContactNoteToApiKeys do
  @moduledoc """
  Step 2 of the personal API keys: roles, expiry and ownership info.

  * `role` is `read_only` or `read_write`, fixed when the key is created
    (the API never changes it afterwards). Existing keys become `read_only`
    through the column default. A check constraint restricts it to the two
    known values.
  * `expires_at` is nullable; NULL means the key never expires. An expired
    key counts as invalid everywhere.
  * `contact` and `note` are optional free text, so it stays clear later
    whose key it is and what it is for.

  `create_api_keys` is already deployed, so it is left untouched and the
  new columns live in this separate migration. `expires_at` uses
  `timestamptz` like the other timestamps (see StacApi.Schema).
  """
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add :role, :string, null: false, default: "read_only"
      add :expires_at, :timestamptz
      add :contact, :string
      add :note, :text
    end

    create constraint(:api_keys, :api_keys_role_check,
             check: "role IN ('read_only', 'read_write')"
           )
  end
end
