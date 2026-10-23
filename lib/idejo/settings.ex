# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings do
  @moduledoc """
  Server-wide settings (AD-02), changed by administrators from the admin panel.

  Each key is declared in `@definitions` with its type, default and checks; a key without a
  stored row uses the default. Every change writes an audit entry (SP-06) in the same
  transaction.

  Secret keys (the SMTP password) are stored encrypted (`Idejo.Settings.Secret`), are never
  put in a form, and appear in the audit log only as `"[changed]"`. Leaving a secret blank in
  a form keeps the saved value.

  Keys in v0.1 so far: the server name (AD-02), the registration mode (AC-02) and outgoing
  email (AD-08), the growing-message window (GM-15, AD-04), the image size limit (TP-12), and
  the About and Rules texts of the welcome card (Markdown), and the server's stylesheet.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Repo
  alias Idejo.Settings.{Secret, Setting}

  @smtp_security ~w(starttls tls none)

  # The server's stylesheet (Admin → Stylesheet): this text until an administrator changes it.
  @default_css_path Path.expand("../../priv/theme/default.css", __DIR__)
  @external_resource @default_css_path
  @default_css @default_css_path |> File.read!() |> String.trim()
  @registration_modes ~w(open invite_only)

  @definitions %{
    server_name: %{type: :string, default: "Idejo", required: true, max: 80},
    # Who may sign up (AC-02): anyone, or only people with an invite.
    registration_mode: %{
      type: :string,
      default: "open",
      required: true,
      in: @registration_modes
    },
    # Sender address of the emails the server sends; defaults to noreply@<host>.
    mail_from: %{type: :string, default: :noreply, required: true, max: 160, format: :email},
    # Outgoing email is off until a host is set.
    smtp_host: %{type: :string, default: "", max: 255, format: :hostname},
    smtp_port: %{type: :integer, default: 587, range: 1..65_535},
    smtp_security: %{type: :string, default: "starttls", required: true, in: @smtp_security},
    smtp_username: %{type: :string, default: "", max: 255},
    smtp_password: %{type: :string, default: "", max: 255, secret: true},
    # Growing messages (GM-03, GM-15): seconds from a message's first commit until its author
    # may start a new one. Server-wide only in v0.1 (MVP); Admin → Settings (AD-04).
    gm_window_seconds: %{type: :integer, default: 15, required: true, range: 2..600},
    # GM-05 (steward decision, 2026-10-23): while nobody has written below a message, its
    # author may start a new one only once it is this many minutes old. Admin → Settings.
    gm_unanswered_minutes: %{type: :integer, default: 10, required: true, range: 1..1440},
    # Uploads (TP-12): the one server-wide size limit for an image, in megabytes (steward
    # decision: 3 by default).
    upload_max_mb: %{type: :integer, default: 3, required: true, range: 1..20},
    # The welcome card and "Rules & Roles" (steward decision, 2026-10-23): Markdown.
    server_about: %{type: :string, default: "", max: 20_000},
    server_rules: %{type: :string, default: "", max: 20_000},
    # The server's stylesheet, served at /theme.css after Idejo's own (steward decision,
    # 2026-10-23).
    custom_css: %{type: :string, default: @default_css, max: 100_000}
  }

  @type key ::
          :server_name
          | :registration_mode
          | :mail_from
          | :smtp_host
          | :smtp_port
          | :smtp_security
          | :smtp_username
          | :smtp_password
          | :gm_window_seconds
          | :gm_unanswered_minutes
          | :upload_max_mb
          | :server_about
          | :server_rules
          | :custom_css

  @doc """
  The allowed values of `:registration_mode`: open, or invite-only (AC-02).
  """
  @spec registration_modes() :: [String.t()]
  def registration_modes, do: @registration_modes

  @doc """
  The allowed values of `:smtp_security`: STARTTLS, implicit TLS, or no encryption.
  """
  @spec smtp_security_values() :: [String.t()]
  def smtp_security_values, do: @smtp_security

  @doc """
  Returns the value of a setting, or its default when it was never set. Secrets come back
  decrypted, or `""` when none is saved or it can no longer be read (e.g. after
  `SECRET_KEY_BASE` changed).
  """
  @spec get(key()) :: String.t() | integer()
  def get(key) when is_map_key(@definitions, key) do
    stored = Repo.get(Setting, Atom.to_string(key))
    decode(key, stored && stored.value)
  end

  @doc """
  Returns every setting with its current value. Secrets are decrypted.
  """
  @spec all() :: %{key() => String.t() | integer()}
  def all do
    stored = Map.new(Repo.all(Setting), &{&1.key, &1.value})
    Map.new(@definitions, fn {key, _} -> {key, decode(key, stored[Atom.to_string(key)])} end)
  end

  @doc """
  Returns true when a secret setting holds a value, so a form can say it is saved.
  """
  @spec secret_set?(key()) :: boolean()
  def secret_set?(key) when is_map_key(@definitions, key), do: get(key) != ""

  @doc """
  Returns a changeset for a settings form, over the current values. Secrets are blank.
  """
  @spec change_settings(map()) :: Ecto.Changeset.t()
  def change_settings(attrs \\ %{}) do
    types = Map.new(@definitions, fn {key, %{type: type}} -> {key, type} end)
    data = Map.new(all(), fn {key, value} -> {key, if(secret?(key), do: "", else: value)} end)

    changeset =
      {data, types}
      |> cast(drop_blank_secrets(attrs), Map.keys(types), empty_values: [])

    Enum.reduce(@definitions, changeset, &validate/2)
  end

  @doc """
  Saves the settings that changed, as `admin`, with one `settings.update` audit entry
  holding the old and new values of the changed keys. Nothing is written when nothing
  changed.
  """
  @spec update_settings(User.t(), map()) ::
          {:ok, %{key() => String.t() | integer()}} | {:error, Ecto.Changeset.t()}
  def update_settings(%User{} = admin, attrs) do
    changeset = change_settings(attrs)

    with {:ok, new} <- apply_action(changeset, :update) do
      save(admin, changeset.data, new, Map.keys(changeset.changes))
    end
  end

  defp save(_admin, _old, new, []), do: {:ok, new}

  defp save(admin, old, new, changed) do
    Repo.transact(fn -> save_changed(admin, old, new, changed) end)
  end

  defp save_changed(admin, old, new, changed) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(changed, fn key ->
        %{
          key: Atom.to_string(key),
          value: encode(key, new[key]),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Setting, rows,
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    with {:ok, _entry} <-
           Audit.record(
             admin,
             "settings.update",
             snapshot(old, changed, "[hidden]"),
             snapshot(new, changed, "[changed]")
           ) do
      {:ok, new}
    end
  end

  # Audit entries never hold a secret.
  defp snapshot(values, keys, secret_placeholder) do
    values
    |> Map.new(fn {key, value} ->
      {key, if(secret?(key), do: secret_placeholder, else: value)}
    end)
    |> Audit.snapshot(keys)
  end

  defp secret?(key), do: Map.get(@definitions[key], :secret, false)

  defp drop_blank_secrets(attrs) do
    Map.reject(attrs, fn {key, value} ->
      key = if is_binary(key), do: String.to_existing_atom(key), else: key
      is_map_key(@definitions, key) and secret?(key) and String.trim(to_string(value)) == ""
    end)
  rescue
    # A key that is not even an atom yet cannot be a setting; cast ignores it.
    ArgumentError -> attrs
  end

  defp validate({key, definition}, changeset) do
    changeset
    |> trim(key, definition)
    |> validate_present(key, definition)
    |> validate_rule(key, :max, definition[:max])
    |> validate_rule(key, :in, definition[:in])
    |> validate_rule(key, :range, definition[:range])
    |> validate_format_of(key, definition[:format])
  end

  defp trim(changeset, key, %{type: :string}),
    do: update_change(changeset, key, &(&1 && String.trim(&1)))

  defp trim(changeset, _key, _definition), do: changeset

  # Blank strings are kept by cast (optional settings may be ""), so required ones are
  # checked here.
  defp validate_present(changeset, key, %{required: true}) do
    if get_field(changeset, key) in [nil, ""],
      do: add_error(changeset, key, "can't be blank", validation: :required),
      else: changeset
  end

  defp validate_present(changeset, _key, _definition), do: changeset

  defp validate_rule(changeset, _key, _rule, nil), do: changeset
  defp validate_rule(changeset, key, :max, max), do: validate_length(changeset, key, max: max)
  defp validate_rule(changeset, key, :in, values), do: validate_inclusion(changeset, key, values)

  defp validate_rule(changeset, key, :range, first..last//_) do
    validate_number(changeset, key, greater_than_or_equal_to: first, less_than_or_equal_to: last)
  end

  defp validate_format_of(changeset, key, :email) do
    validate_format(changeset, key, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
  end

  defp validate_format_of(changeset, key, :hostname) do
    validate_format(changeset, key, ~r/^([A-Za-z0-9-]+\.)*[A-Za-z0-9-]+$|^$/,
      message: "must be a host name such as smtp.example.org"
    )
  end

  defp validate_format_of(changeset, _key, nil), do: changeset

  defp decode(key, nil), do: default(key)

  defp decode(key, value) do
    case @definitions[key] do
      %{secret: true} -> Secret.decrypt(value) || ""
      %{type: :integer} -> String.to_integer(value)
      %{type: :string} -> value
    end
  end

  defp encode(key, value) do
    case @definitions[key] do
      %{secret: true} -> Secret.encrypt(value)
      _ -> to_string(value)
    end
  end

  @doc "A setting's default value: what it is until an administrator changes it."
  @spec default(key()) :: String.t() | integer()
  def default(key) when is_map_key(@definitions, key) do
    case @definitions[key].default do
      :noreply ->
        "noreply@" <> (URI.parse(Application.fetch_env!(:idejo, :base_uri)).host || "localhost")

      default ->
        default
    end
  end
end
