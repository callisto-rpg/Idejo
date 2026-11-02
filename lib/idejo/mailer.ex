# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Mailer do
  @moduledoc """
  Sends email. In production the SMTP server comes from the admin panel's email settings
  (AD-08), read at each send, so a change applies at once. While the panel has no SMTP host,
  the server set in the environment (`IDEJO_SMTP_*`, AD-13) is used instead, whole: the two
  are never mixed. Development keeps Swoosh's local mailbox (`/dev/mailbox`) and tests the
  test adapter.
  """
  use Swoosh.Mailer, otp_app: :idejo

  alias Idejo.Settings

  @doc """
  Delivers an email with the configured adapter, using the saved SMTP settings when the
  adapter is SMTP. Returns `{:error, :smtp_not_configured}` while no SMTP host is set.
  """
  @spec deliver_email(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver_email(%Swoosh.Email{} = email) do
    if smtp?() do
      with {:ok, config} <- smtp_config(smtp_settings(Settings.all())),
           do: deliver(email, config)
    else
      deliver(email)
    end
  end

  defp smtp?, do: Application.get_env(:idejo, __MODULE__)[:adapter] == Swoosh.Adapters.SMTP

  @doc """
  The SMTP server from the environment (`IDEJO_SMTP_*`, read by `config/runtime.exs`), or
  nil when none is set.
  """
  @spec environment() :: keyword() | nil
  def environment, do: Application.get_env(:idejo, :smtp_environment)

  @doc """
  The SMTP settings email goes through: the panel's (`settings`, from `Settings.all/0`) once
  they have a host, else the environment's (AD-13), else the panel's empty ones.
  """
  @spec smtp_settings(map(), keyword() | nil) :: map()
  def smtp_settings(settings, environment \\ environment())

  def smtp_settings(%{smtp_host: ""} = settings, [_ | _] = env) do
    %{
      settings
      | smtp_host: env[:host],
        smtp_port: env[:port],
        smtp_security: env[:security],
        smtp_username: env[:username],
        smtp_password: env[:password]
    }
  end

  def smtp_settings(settings, _environment), do: settings

  @doc """
  The sender address of the server's emails: `IDEJO_SMTP_FROM` while the environment's SMTP
  server is in use and it is set, else the panel's sender address.
  """
  @spec from_address() :: String.t()
  def from_address do
    with [_ | _] = env <- environment(),
         from when is_binary(from) <- env[:from],
         "" <- Settings.get(:smtp_host) do
      from
    else
      _ -> Settings.get(:mail_from)
    end
  end

  @doc """
  Builds the Swoosh SMTP adapter options from the email settings.

  Certificates are always verified against the system's trusted authorities: `starttls`
  requires STARTTLS, `tls` connects with TLS from the start (usually port 465), and `none`
  sends unencrypted, for a relay on the same machine or network only.
  """
  @spec smtp_config(map()) :: {:ok, keyword()} | {:error, :smtp_not_configured}
  def smtp_config(%{smtp_host: ""}), do: {:error, :smtp_not_configured}

  def smtp_config(%{smtp_host: host} = settings) do
    tls_options = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      depth: 10
    ]

    security =
      case settings.smtp_security do
        "starttls" -> [ssl: false, tls: :always, tls_options: tls_options]
        "tls" -> [ssl: true, tls: :never, sockopts: tls_options]
        "none" -> [ssl: false, tls: :never]
      end

    auth =
      case settings.smtp_username do
        "" -> [auth: :never]
        username -> [auth: :always, username: username, password: settings.smtp_password]
      end

    {:ok,
     [
       adapter: Swoosh.Adapters.SMTP,
       relay: host,
       port: settings.smtp_port,
       retries: 1,
       no_mx_lookups: true
     ] ++ security ++ auth}
  end
end
