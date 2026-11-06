# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.OIDCRegistry do
  @moduledoc """
  Connecting to Idejo ID from the admin panel (AC-09; steward decisions, 2026-11-06): an
  install with no OpenID Connect provider in its environment registers itself as a client of
  an Idejo ID registry (`IDEJO_ID_REGISTRY_URL`, by default `https://login.idejo.org`; `off`
  hides it), then may ask to be listed in that registry's directory of forums.

  The registry's protocol (JSON under `<registry>/account/api`):

    1. `POST registrations` `{host, name}` → `{registration, proof}`;
    2. this server serves `proof` at `/.well-known/idejo-id-registration` (`proof/0`, kept
       in a settings row for ten minutes, so any of the server's processes answers it);
    3. `POST registrations/verify` `{registration}`: the registry fetches the proof and
       answers `{issuer, client_id, client_secret, label, sign_up_url, directory_url}`;
    4. `GET`/`PUT listing` `{listed, name}` with the client id and secret (HTTP Basic) →
       `{listing}`: `none`, `requested`, `approved`, `refused`.

  The connection is kept in settings rows outside `Idejo.Settings`'s definitions (no form
  changes them; backups carry them), the secret encrypted (`Settings.Secret`), and in a
  persistent term for `Idejo.Accounts.OIDC.config/0` (loaded at boot by `child_spec/1`). The
  environment's `IDEJO_OIDC_*`, when set, always wins: connecting is then not offered.
  Audited `oidc.connect`, `oidc.disconnect`, `oidc.listing` (never the secret).

  Changes to this module get an extra careful human review (DV-06).
  """
  import Ecto.Query

  alias Idejo.Accounts.{OIDC, User}
  alias Idejo.{Audit, Repo, Settings}
  alias Idejo.Settings.{Secret, Setting}

  @connection "oidc_registration"
  @secret "oidc_registration_secret"
  @proof "oidc_registration_proof"
  @listing "oidc_directory_listing"
  @term {__MODULE__, :connection}
  @proof_seconds 600

  ## Configuration

  @doc "The registry this server may connect to (`IDEJO_ID_REGISTRY_URL`), or nil."
  @spec registry_url() :: String.t() | nil
  def registry_url, do: Application.get_env(:idejo, :id_registry_url)

  @doc "The connection made from the admin panel, as `config :idejo, :oidc` would be, or nil."
  @spec config() :: keyword() | nil
  def config, do: :persistent_term.get(@term, nil)

  @doc "Whether this server is connected from the admin panel."
  @spec connected?() :: boolean()
  def connected?, do: config() != nil

  @doc false
  # Loads the connection after the repo starts, and starts its provider worker.
  def child_spec(_arg),
    do: %{id: __MODULE__, start: {Task, :start_link, [&boot/0]}, restart: :temporary}

  defp boot do
    load()
    if config() && !Application.get_env(:idejo, :oidc), do: start_worker()
    :ok
  end

  @doc "Reads the connection from the database into the persistent term."
  @spec load() :: :ok
  def load do
    rows =
      Map.new(
        Repo.all(from s in Setting, where: s.key in [@connection, @secret]),
        &{&1.key, &1.value}
      )

    with %{} = saved <- decode(rows[@connection]),
         secret when is_binary(secret) <- rows[@secret] && Secret.decrypt(rows[@secret]) do
      :persistent_term.put(@term,
        issuer: saved["issuer"],
        client_id: saved["client_id"],
        client_secret: secret,
        label: saved["label"],
        sign_up_url: saved["sign_up_url"],
        directory_url: saved["directory_url"],
        registry_url: saved["registry_url"]
      )
    else
      _ -> forget()
    end

    :ok
  end

  @doc false
  def forget do
    if :persistent_term.get(@term, nil), do: :persistent_term.erase(@term)
  end

  defp decode(nil), do: nil

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> map
      _ -> nil
    end
  end

  ## Connecting

  @doc """
  Connects this server to the registry as `admin`: `{:ok, label}`, or `{:error, message}`
  (the registry's own message when it gave one).
  """
  @spec connect(User.t()) :: {:ok, String.t()} | {:error, String.t() | atom()}
  def connect(%User{} = admin) do
    with url when is_binary(url) <- registry_url() || {:error, :no_registry},
         nil <- Application.get_env(:idejo, :oidc) && {:error, :environment},
         {:ok, %{"registration" => registration, "proof" => proof}} <-
           call(:post, url, "/registrations",
             json: %{host: host(), name: Settings.get(:server_name)}
           ),
         :ok <- put_proof(proof),
         {:ok, creds} <- verify(url, registration),
         {:ok, connection} <- check(creds, url) do
      save(admin, connection)
      {:ok, connection[:label]}
    end
  end

  defp verify(url, registration) do
    call(:post, url, "/registrations/verify",
      json: %{registration: registration},
      receive_timeout: 20_000
    )
  after
    Repo.delete_all(from s in Setting, where: s.key == @proof)
  end

  defp check(
         %{"issuer" => "http" <> _ = issuer, "client_id" => id, "client_secret" => secret} = creds,
         url
       )
       when is_binary(id) and id != "" and is_binary(secret) and secret != "" do
    {:ok,
     [
       issuer: issuer,
       client_id: id,
       client_secret: secret,
       label: text(creds["label"]) || "Idejo ID",
       sign_up_url: link(creds["sign_up_url"]),
       directory_url: link(creds["directory_url"]),
       registry_url: url
     ]}
  end

  defp check(_creds, _url), do: {:error, :bad_answer}

  defp text(value) when is_binary(value) and value != "", do: String.slice(value, 0, 60)
  defp text(_value), do: nil

  defp link("http" <> _ = value), do: value
  defp link(_value), do: nil

  defp save(admin, connection) do
    {:ok, _} =
      Repo.transaction(fn ->
        public = connection |> Keyword.delete(:client_secret) |> Map.new()
        now = DateTime.utc_now(:second)

        Repo.insert_all(
          Setting,
          [
            %{key: @connection, value: Jason.encode!(public), inserted_at: now, updated_at: now},
            %{
              key: @secret,
              value: Secret.encrypt(connection[:client_secret]),
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:value, :updated_at]},
          conflict_target: :key
        )

        Repo.delete_all(from s in Setting, where: s.key == @listing)

        Audit.record(admin, "oidc.connect", %{}, %{
          "issuer" => public.issuer,
          "client_id" => public.client_id
        })
      end)

    load()
    start_worker()
  end

  @doc "Disconnects: sign-in with the provider stops here (links to it are kept)."
  @spec disconnect(User.t()) :: :ok
  def disconnect(%User{} = admin) do
    if connected?(), do: set_listing_remote(false)

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.delete_all(from s in Setting, where: s.key in [@connection, @secret, @listing])
        Audit.record(admin, "oidc.disconnect", %{"issuer" => config()[:issuer]}, %{})
      end)

    forget()
    stop_worker()
    :ok
  end

  ## The proof

  defp put_proof(proof) when is_binary(proof) and byte_size(proof) <= 200 do
    now = DateTime.utc_now(:second)
    value = Jason.encode!(%{proof: proof, until: DateTime.to_unix(now) + @proof_seconds})

    Repo.insert_all(Setting, [%{key: @proof, value: value, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    :ok
  end

  defp put_proof(_proof), do: {:error, :bad_answer}

  @doc "The proof being asked for, while a connection is under way, or nil."
  @spec proof() :: String.t() | nil
  def proof do
    with %Setting{value: value} <- Repo.get(Setting, @proof),
         %{"proof" => proof, "until" => until} <- decode(value),
         true <- until > System.system_time(:second) do
      proof
    else
      _ -> nil
    end
  end

  ## The directory

  @doc """
  This server's listing in the registry's directory: `{:ok, status}` (`none`, `requested`,
  `approved`, `refused`), asked again (two seconds at most), else the one last known.
  """
  @spec listing() :: {:ok, String.t()} | {:error, :not_connected}
  def listing do
    if connected?() do
      case call(:get, config()[:registry_url], "/listing", auth: auth(), receive_timeout: 2_000) do
        {:ok, %{"listing" => status}} when is_binary(status) -> {:ok, keep(status)}
        _ -> {:ok, known_listing()}
      end
    else
      {:error, :not_connected}
    end
  end

  defp known_listing do
    case Repo.get(Setting, @listing) do
      %Setting{value: status} -> status
      nil -> "none"
    end
  end

  @doc "Asks to be listed in the directory (`listed?` true) or to leave it, as `admin`."
  @spec set_listed(User.t(), boolean()) :: {:ok, String.t()} | {:error, term()}
  def set_listed(%User{} = admin, listed?) do
    with true <- connected?() || {:error, :not_connected},
         {:ok, status} <- set_listing_remote(listed?) do
      Audit.record(admin, "oidc.listing", %{}, %{"listed" => listed?, "listing" => status})
      {:ok, status}
    end
  end

  defp set_listing_remote(listed?) do
    case call(:put, config()[:registry_url], "/listing",
           auth: auth(),
           json: %{listed: listed?, name: Settings.get(:server_name)}
         ) do
      {:ok, %{"listing" => status}} when is_binary(status) -> {:ok, keep(status)}
      {:error, _} = error -> error
      _ -> {:error, :bad_answer}
    end
  end

  defp keep(status) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(Setting, [%{key: @listing, value: status, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    status
  end

  defp auth, do: {:basic, config()[:client_id] <> ":" <> config()[:client_secret]}

  ## The registry

  defp call(method, url, path, options) do
    request =
      Req.new(
        method: method,
        url: String.trim_trailing(url, "/") <> "/account/api" <> path,
        retry: false,
        redirect: false,
        receive_timeout: 15_000,
        connect_options: [timeout: 5_000]
      )
      |> Req.merge(options)
      |> Req.merge(Application.get_env(:idejo, :id_registry_req_options, []))

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{body: %{"message" => message}}} when is_binary(message) ->
        {:error, String.slice(message, 0, 300)}

      {:ok, %Req.Response{}} ->
        {:error, :bad_answer}

      {:error, _exception} ->
        {:error, :unreachable}
    end
  end

  defp host, do: :idejo |> Application.fetch_env!(:base_uri) |> URI.parse() |> Map.fetch!(:host)

  ## The worker

  defp start_worker do
    if Application.get_env(:idejo, :id_registry_start_worker, true) do
      stop_worker()
      Supervisor.start_child(Idejo.Supervisor, hd(OIDC.worker_specs(config())))
    end

    :ok
  end

  defp stop_worker do
    if Application.get_env(:idejo, :id_registry_start_worker, true) do
      Supervisor.terminate_child(Idejo.Supervisor, Oidcc.ProviderConfiguration.Worker)
      Supervisor.delete_child(Idejo.Supervisor, Oidcc.ProviderConfiguration.Worker)
    end

    :ok
  end
end
