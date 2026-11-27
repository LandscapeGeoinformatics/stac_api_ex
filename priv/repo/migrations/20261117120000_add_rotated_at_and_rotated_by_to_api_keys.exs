defmodule StacApi.Repo.Migrations.AddRotatedAtAndRotatedByToApiKeys do
  @moduledoc """
  Step 3 of the personal API keys: self-service rotation and max-age.

  * `rotated_at` is when the current secret was issued (created or last
    rotated). The optional max-age counts from here. Existing keys get the
    time of this migration through the column default, deliberately not
    `inserted_at`: otherwise switching max-age on would kill every older key
    at once. New rows that do not set it get `now()` as well.
  * `rotated_by` is `admin` or `self` after a rotation and NULL for a key
    that was never rotated, so a self-rotation the owner did not do can be
    spotted in the admin listing.
  """
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add :rotated_at, :timestamptz, null: false, default: fragment("now()")
      add :rotated_by, :string
    end

    create constraint(:api_keys, :api_keys_rotated_by_check,
             check: "rotated_by IS NULL OR rotated_by IN ('admin', 'self')"
           )
  end
end
