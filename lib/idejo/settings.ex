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
  the About and Rules texts of the welcome card (Markdown), the server's stylesheet, the
  website theme's colours and the forum's logo (AD-11).
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Idejo.Accounts.ApiTokens
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Repo
  alias Idejo.Settings.{Secret, Setting, Stylesheet}

  @smtp_security ~w(starttls tls none)

  # The server's stylesheet (Admin → Stylesheet): this text until an administrator changes it.
  @default_css_path Path.expand("../../priv/theme/default.css", __DIR__)
  @external_resource @default_css_path
  @default_css @default_css_path |> File.read!() |> String.trim()
  @registration_modes ~w(open invite_only closed)
  # PN-16: the push services of Chrome and Edge (FCM), Firefox, Safari and Windows.
  @push_services Enum.join(
                   ~w(fcm.googleapis.com updates.push.services.mozilla.com *.push.apple.com
                      *.notify.windows.com),
                   "\n"
                 )

  @definitions %{
    server_name: %{type: :string, default: "Idejo", required: true, max: 80},
    # Who may sign up (AC-02): anyone, only people with an invite, or nobody (closed; steward
    # decision, 2026-11-02, for AD-14).
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
    gm_window_seconds: %{type: :integer, default: 15, required: true, range: 0..600},
    # GM-05 (steward decision, 2026-10-23): while nobody has written below a message, its
    # author may start a new one only once it is this many minutes old. Admin → Settings.
    # Decimals allowed, from 0.1 (six seconds; steward request, 2026-11-09).
    gm_unanswered_minutes: %{
      type: :float,
      default: 10,
      required: true,
      min: 0.1,
      max_value: 1440
    },
    # Reply starts a new message at any time (steward decision, 2026-10-24): sending it
    # completes the author's open message even while its timer runs. Admin → Settings.
    gm_early_reply: %{type: :boolean, default: true},
    # Topics nobody follows are shown faded as "inactive" (steward decision, 2026-11-01):
    # Idejo.Reading.put_inactive/1. Admin → Settings.
    inactive_topics: %{type: :boolean, default: true},
    # Topics with no message for this many days are inactive too, followed or not.
    inactive_after_days: %{type: :integer, default: 70, required: true, range: 7..3650},
    # Uploads (TP-12): the one server-wide size limit for an image, in megabytes (steward
    # decision: 3 by default).
    upload_max_mb: %{type: :integer, default: 3, required: true, range: 1..20},
    # How many messages a topic loads at a time (steward decision, 2026-11-01):
    # Idejo.Forum.TopicWindow.sizes/1.
    performance: %{type: :string, default: "normal", required: true, in: ~w(light normal heavy)},
    # The welcome card and "Rules & Roles" (steward decision, 2026-10-23): Markdown.
    server_about: %{type: :string, default: "", max: 20_000},
    server_rules: %{type: :string, default: "", max: 20_000},
    # The privacy notice at /privacy (AD-02, legal pages): Markdown.
    privacy_notice: %{type: :string, default: "", max: 50_000},
    # PN-19: web push notifications, on by default; "off" means no banner, no subscribing
    # and no sending.
    push_enabled: %{type: :string, default: "on", required: true, in: ~w(on off)},
    # AP-20 (steward decision, 2026-11-10): the official app's API, its sign-in page and its
    # socket. Off, they answer 404 and device tokens are refused, but kept.
    api_enabled: %{type: :boolean, default: true},
    # PN-04: at most one "new messages in topics you follow" push per user in this time.
    push_followed_interval_minutes: %{
      type: :integer,
      default: 30,
      required: true,
      range: 1..1440
    },
    # PN-16: the push services the server sends to, one host per line; "*.example.com"
    # allows any name under example.com.
    push_services: %{
      type: :string,
      default: @push_services,
      required: true,
      max: 2000,
      format: :host_patterns
    },
    # GIFs in the composer (steward decisions, 2026-11-03; Idejo.Gifs): the provider's key,
    # empty for off. Not a secret: every browser that searches receives it.
    gif_api_key: %{type: :string, default: "", max: 255},
    # The provider's content safety filter.
    gif_content_filter: %{
      type: :string,
      default: "medium",
      required: true,
      in: ~w(off low medium high)
    },
    # The server's stylesheet, served at /theme.css after Idejo's own (steward decision,
    # 2026-10-23).
    # AD-11: loads nothing from elsewhere, runs nothing (Idejo.Settings.Stylesheet).
    custom_css: %{type: :string, default: @default_css, max: 100_000, format: :stylesheet},
    # The website theme (steward decision, 2026-10-24): buttons, toggles, links and the page
    # backgrounds, as #rrggbb or #rrggbbaa. Admin → Settings.
    theme_primary: %{type: :string, default: "#daa304ff", required: true, format: :colour},
    theme_secondary: %{type: :string, default: "#f2c94c", required: true, format: :colour},
    theme_tertiary: %{type: :string, default: "#b8860b", required: true, format: :colour},
    theme_light_bg: %{type: :string, default: "#fdfcf6", required: true, format: :colour},
    theme_dark_bg: %{type: :string, default: "#1d1a00", required: true, format: :colour},
    # AD-11: the forum's own logo in the header, an upload's address
    # (`Idejo.Settings.Logo`); empty for Idejo's small logo.
    brand_logo: %{type: :string, default: "", max: 100, format: :logo}
  }

  @theme_names [
    theme_primary: :primary,
    theme_secondary: :secondary,
    theme_tertiary: :tertiary,
    theme_light_bg: :light_bg,
    theme_dark_bg: :dark_bg
  ]
  @theme_keys Keyword.keys(@theme_names)

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
          | :gm_early_reply
          | :inactive_topics
          | :inactive_after_days
          | :upload_max_mb
          | :performance
          | :server_about
          | :server_rules
          | :privacy_notice
          | :push_enabled
          | :api_enabled
          | :push_followed_interval_minutes
          | :push_services
          | :gif_api_key
          | :gif_content_filter
          | :custom_css
          | :theme_primary
          | :theme_secondary
          | :theme_tertiary
          | :theme_light_bg
          | :theme_dark_bg
          | :brand_logo

  @doc """
  The allowed values of `:registration_mode`: open, invite-only (AC-02), or closed: nobody
  signs up, not even with an invite (steward decision, 2026-11-02).
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
  @spec get(key()) :: String.t() | integer() | boolean()
  def get(key) when is_map_key(@definitions, key) do
    name = Atom.to_string(key)

    # A page reads a dozen settings: all of them at once while Idejo.Memo is on (one request
    # or mount), else this one alone.
    if Idejo.Memo.on?() do
      decode(key, stored()[name])
    else
      stored = Repo.get(Setting, name)
      decode(key, stored && stored.value)
    end
  end

  # Every stored value, read once while Idejo.Memo is on.
  defp stored do
    Idejo.Memo.fetch(:settings, fn -> Map.new(Repo.all(Setting), &{&1.key, &1.value}) end)
  end

  @doc """
  Returns every setting with its current value. Secrets are decrypted.
  """
  @spec all() :: %{key() => String.t() | integer() | boolean()}
  def all do
    stored = stored()
    Map.new(@definitions, fn {key, _} -> {key, decode(key, stored[Atom.to_string(key)])} end)
  end

  @doc """
  The website theme's colours (steward decision, 2026-10-24), keyed by `:primary`,
  `:secondary`, `:tertiary`, `:light_bg` and `:dark_bg`, in one query: every page reads them.
  """
  @spec theme() :: %{atom() => String.t()}
  def theme do
    stored = stored()

    Map.new(@theme_names, fn {key, name} -> {name, decode(key, stored[Atom.to_string(key)])} end)
  end

  @doc "The theme's setting keys, in the order Admin → Settings shows them."
  @spec theme_keys() :: [key()]
  def theme_keys, do: @theme_keys

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
  changed. `admin` must be an owner or administrator (`{:error, :forbidden}` otherwise);
  `nil` is the setup itself (`Idejo.Setup`, before anyone has a role), never a request.
  """
  @spec update_settings(User.t() | nil, map()) ::
          {:ok, %{key() => String.t() | integer() | boolean()}}
          | {:error, :forbidden | Ecto.Changeset.t()}
  def update_settings(nil, attrs), do: save_settings(nil, attrs)

  def update_settings(%User{} = admin, attrs),
    do: Idejo.Access.as_administrator(admin, fn -> save_settings(admin, attrs) end)

  defp save_settings(admin, attrs) do
    changeset = change_settings(attrs)

    with {:ok, new} <- apply_action(changeset, :update) do
      save(admin, changeset.data, new, Map.keys(changeset.changes))
    end
  end

  defp save(_admin, _old, new, []), do: {:ok, new}

  defp save(admin, old, new, changed) do
    with {:ok, new} <- Repo.transact(fn -> save_changed(admin, old, new, changed) end) do
      announce(changed)
      # AP-20: the app's sockets end at once.
      if :api_enabled in changed and new[:api_enabled] == false,
        do: ApiTokens.announce_disabled()

      {:ok, new}
    end
  end

  @doc """
  Subscribes the caller to setting changes: `{:settings_changed, keys}` after each save,
  with the keys that changed (the app's `settings.changed`, AP-15; the API's switch, AP-20).
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Idejo.PubSub, "settings")

  defp announce(changed),
    do: Phoenix.PubSub.broadcast(Idejo.PubSub, "settings", {:settings_changed, changed})

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

    :ok = Idejo.Memo.forget()

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
    |> validate_rule(key, :min, definition[:min])
    |> validate_rule(key, :max_value, definition[:max_value])
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

  defp validate_rule(changeset, key, :min, min),
    do: validate_number(changeset, key, greater_than_or_equal_to: min)

  defp validate_rule(changeset, key, :max_value, max),
    do: validate_number(changeset, key, less_than_or_equal_to: max)

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

  defp validate_format_of(changeset, key, :host_patterns) do
    validate_change(changeset, key, fn ^key, value ->
      patterns = String.split(value, ["\n", "\r", ",", " "], trim: true)

      if Enum.all?(patterns, &Regex.match?(~r/^(\*\.)?([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$/, &1)),
        do: [],
        else: [{key, "must be host names such as push.example.org, one per line"}]
    end)
  end

  defp validate_format_of(changeset, key, :colour) do
    changeset
    |> update_change(key, &(&1 && String.downcase(&1)))
    |> validate_format(key, ~r/^#[0-9a-f]{6}([0-9a-f]{2})?$/,
      message: "must look like #daa304 or #daa304ff"
    )
  end

  # Only a logo Idejo.Settings.Logo stored: a WebP upload.
  defp validate_format_of(changeset, key, :logo) do
    validate_format(changeset, key, ~r"^(/uploads/[0-9a-f-]{36}\.webp)?$",
      message: "must be an uploaded logo"
    )
  end

  defp validate_format_of(changeset, key, :stylesheet) do
    validate_change(changeset, key, fn ^key, css ->
      case Stylesheet.check(css || "") do
        :ok -> []
        {:error, reason} -> [{key, reason}]
      end
    end)
  end

  defp validate_format_of(changeset, _key, nil), do: changeset

  defp decode(key, nil), do: default(key)

  defp decode(key, value) do
    case @definitions[key] do
      %{secret: true} -> Secret.decrypt(value) || ""
      %{type: :integer} -> String.to_integer(value)
      %{type: :float} -> to_number(value)
      %{type: :boolean} -> value == "true"
      %{type: :string} -> value
    end
  end

  # A whole number reads as one ("10", stored before decimals), else a float ("0.5").
  defp to_number(value) do
    case Integer.parse(value) do
      {n, ""} ->
        n

      _ ->
        {f, _} = Float.parse(value)
        f
    end
  end

  defp encode(key, value) do
    case @definitions[key] do
      %{secret: true} -> Secret.encrypt(value)
      %{type: :float} when is_float(value) and value == trunc(value) -> to_string(trunc(value))
      _ -> to_string(value)
    end
  end

  @doc "A setting's default value: what it is until an administrator changes it."
  @spec default(key()) :: String.t() | number() | boolean()
  def default(key) when is_map_key(@definitions, key) do
    case @definitions[key].default do
      :noreply ->
        "noreply@" <> (URI.parse(Application.fetch_env!(:idejo, :base_uri)).host || "localhost")

      default ->
        default
    end
  end
end
