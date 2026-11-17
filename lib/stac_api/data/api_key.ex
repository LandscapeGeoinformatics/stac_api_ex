defmodule StacApi.Data.ApiKey do
  @moduledoc """
  A personalized API key issued through the management API.

  Independent of the static keys configured via STAC_API_KEY /
  STAC_API_KEY_RO. Each key has a `role`, fixed at creation: `"read_only"`
  keys read the public STAC API (see ReadAuthPlug), `"read_write"` keys can
  also write catalogs, collections and items. Neither can manage keys; that
  stays with the static STAC_API_KEY.

  A key can have an `expires_at`; once it has passed the key is invalid
  everywhere (`get_by_secret/1` no longer returns it). With the optional
  max-age configured (`STAC_API_KEY_MAX_AGE_DAYS`) the secret also stops
  working that many days after `rotated_at`; see `secret_expires_at/1`.
  `contact` and `note` are optional free text recording whose key it is and
  what it is for.

  `rotated_at` is when the current secret was issued (created or last
  rotated) and `rotated_by` is `"admin"` or `"self"` after a rotation.

  Only `key_hash` is persisted. The raw secret exists only in memory at
  creation/rotation time and in the response body returned to the caller
  at that moment — it cannot be recovered afterwards, only rotated.
  """
  use StacApi.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias StacApi.Repo

  @roles ["read_only", "read_write"]
  @rotators ["admin", "self"]
  @prefixes %{"read_only" => "stac_ro_", "read_write" => "stac_rw_"}

  # last_used_at is refreshed at most this often, to avoid a write per request.
  @last_used_interval_seconds 3600

  schema "api_keys" do
    field :name, :string
    field :key_hash, :string
    field :key_prefix, :string
    field :role, :string, default: "read_only"
    field :expires_at, :utc_datetime_usec
    field :contact, :string
    field :note, :string
    field :last_used_at, :utc_datetime_usec
    # When the current secret was issued (created or last rotated), and who
    # rotated it ("admin" or "self"; nil if never rotated).
    field :rotated_at, :utc_datetime_usec, read_after_writes: true
    field :rotated_by, :string

    timestamps()
  end

  @doc """
  Builds a changeset for creating a key, or for replacing its secret on rotate.

  Casts `:name`, `:key_hash`, `:key_prefix`, `:role`, `:expires_at`,
  `:contact` and `:note`; name, hash and prefix are required. The name is
  trimmed and must be 1-100 characters and unique; `:key_hash` must be unique.
  `:role` must be `"read_only"` or `"read_write"` and `:expires_at` must lie in
  the future. Callers building a key from user input should take hash and
  prefix from `generate_secret/1`. To edit an existing key use
  `update_changeset/2`, which cannot change the role.
  """
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :key_hash, :key_prefix, :role, :expires_at, :contact, :note])
    |> validate_required([:name, :key_hash, :key_prefix])
    |> validate_inclusion(:role, @roles)
    |> validate_editable_fields()
    |> unique_constraint(:key_hash)
  end

  @doc """
  Builds a changeset for editing an existing key (PATCH).

  Only `:name`, `:expires_at`, `:contact` and `:note` are cast. The role and
  the secret are not editable here: a role change means issuing a new key and
  deleting the old one.
  """
  def update_changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :expires_at, :contact, :note])
    |> validate_required([:name])
    |> validate_editable_fields()
  end

  # Rules shared by create and update.
  defp validate_editable_fields(changeset) do
    changeset
    |> update_change(:name, &trim_name/1)
    |> validate_length(:name, max: 100)
    |> validate_length(:contact, max: 255)
    |> validate_change(:expires_at, fn :expires_at, expires_at ->
      if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
        do: [],
        else: [expires_at: "must be in the future"]
    end)
    |> unique_constraint(:name)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  @doc """
  Returns the valid key whose secret is `raw_secret`, or `nil`.

  Looks the key up by the SHA-256 hash of the secret, which is all that is
  stored. A key whose `expires_at` has passed is not returned, so this is the
  single place that decides whether an issued key is usable. Non-binary input
  returns `nil`.
  """
  def get_by_secret(raw_secret) when is_binary(raw_secret) do
    now = DateTime.utc_now()

    query =
      from k in __MODULE__,
        where: k.key_hash == ^hash(raw_secret) and (is_nil(k.expires_at) or k.expires_at > ^now)

    query
    |> within_max_age(now)
    |> Repo.one()
  end

  def get_by_secret(_), do: nil

  # With a max-age configured, the secret must have been issued less than that
  # many days ago. Without one, nothing is added.
  defp within_max_age(query, now) do
    case max_age_days() do
      nil ->
        query

      days ->
        cutoff = DateTime.add(now, -days * 86_400, :second)
        where(query, [k], k.rotated_at > ^cutoff)
    end
  end

  @doc """
  The configured max-age of a secret in days (`STAC_API_KEY_MAX_AGE_DAYS`), or
  `nil` when it is off.
  """
  def max_age_days, do: Application.get_env(:stac_api, :api_key_max_age_days)

  @doc """
  The moment the current secret of `api_key` stops working, or `nil`.

  This is `min(expires_at, rotated_at + max_age)`: the admin's `expires_at`
  and, when a max-age is configured, the end of the secret's max-age. `nil`
  when neither applies.
  """
  def secret_expires_at(%__MODULE__{expires_at: expires_at, rotated_at: rotated_at}) do
    max_age_end =
      case max_age_days() do
        nil -> nil
        days -> DateTime.add(rotated_at, days * 86_400, :second)
      end

    [expires_at, max_age_end]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.min(dates, DateTime)
    end
  end

  @doc """
  The access level an issued key grants: `:read_write` or `:read_only`.
  """
  def auth_level(%__MODULE__{role: "read_write"}), do: :read_write
  def auth_level(%__MODULE__{}), do: :read_only

  @doc """
  Records that `api_key` was just used, at most once per hour.

  Skips the write when the loaded `last_used_at` is recent. Otherwise it is a
  single conditional UPDATE, so concurrent requests cannot both write.
  `last_used_at` is therefore accurate to about an hour. Returns `:ok`.
  """
  def touch_last_used(%__MODULE__{id: id, last_used_at: last_used_at}) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@last_used_interval_seconds, :second)

    if is_nil(last_used_at) or DateTime.compare(last_used_at, cutoff) == :lt do
      Repo.update_all(
        from(k in __MODULE__,
          where: k.id == ^id and (is_nil(k.last_used_at) or k.last_used_at < ^cutoff)
        ),
        set: [last_used_at: now]
      )
    end

    :ok
  end

  @doc """
  Replaces the secret of `api_key` with a fresh one and records the rotation.

  Only the secret, `key_prefix`, `rotated_at` and `rotated_by` change: the
  role, name, `expires_at`, `contact` and `note` stay as they are, so a
  rotation can never move the admin's `expires_at`. `rotated_by` is `"admin"`
  or `"self"`. Returns `{:ok, api_key, raw_secret}`; the raw secret is shown to
  the caller once. Returns `{:error, changeset}` if the update fails.
  """
  def rotate_secret(%__MODULE__{} = api_key, rotated_by) when rotated_by in @rotators do
    {raw_secret, secret_attrs} = generate_secret(api_key.role)

    changeset =
      api_key
      |> cast(secret_attrs, [:key_hash, :key_prefix])
      |> change(rotated_at: DateTime.utc_now(), rotated_by: rotated_by)
      |> unique_constraint(:key_hash)

    case Repo.update(changeset) do
      {:ok, updated} -> {:ok, updated, raw_secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Generates a fresh random secret for `role` plus the attrs to persist for it.
  Returns `{raw_secret, attrs}` — `raw_secret` is shown to the caller once
  and is not itself stored. The secret starts with `stac_rw_` for
  `"read_write"` and `stac_ro_` otherwise, so `key_prefix` follows the role.
  """
  def generate_secret(role \\ "read_only") do
    prefix = Map.get(@prefixes, role, "stac_ro_")
    raw = prefix <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))
    {raw, %{key_hash: hash(raw), key_prefix: String.slice(raw, 0, 12)}}
  end

  @doc "SHA-256 hex digest used to look up a key by its raw secret."
  def hash(raw_secret) when is_binary(raw_secret) do
    :crypto.hash(:sha256, raw_secret) |> Base.encode16(case: :lower)
  end
end
