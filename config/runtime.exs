# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/idejo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :idejo, IdejoWeb.Endpoint, server: true
end

config :idejo, IdejoWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :idejo, IdejoWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/idejo_web/router\.ex$"E,
        ~r"lib/idejo_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# AD-05: where pg_dump and pg_restore are, when not on the PATH (they must match the
# PostgreSQL server's major version).
if pg_bin_dir = System.get_env("IDEJO_PG_BIN_DIR") do
  config :idejo, :pg_bin_dir, pg_bin_dir
end

# LI-03: where a modified server publishes its own source code.
if source_url = System.get_env("IDEJO_SOURCE_URL") do
  config :idejo, :source_url, source_url
end

# AD-16: the reverse proxies whose X-Forwarded-For, -Proto and -Host are believed
# (IdejoWeb.Plugs.ClientIp): IP addresses and CIDR ranges, separated by commas. Unset, peers
# on a private network are, which covers the bundled Caddy. A malformed list stops the boot.
case System.get_env("IDEJO_TRUSTED_PROXIES", "") |> String.trim() do
  "" ->
    :ok

  list ->
    invalid = fn entry ->
      raise """
      environment variable IDEJO_TRUSTED_PROXIES has an invalid entry: #{inspect(entry)}.
      Give IP addresses or CIDR ranges separated by commas, for example
      IDEJO_TRUSTED_PROXIES=10.0.0.5,172.18.0.0/16,fd00::/8
      """
    end

    proxies =
      for entry <- String.split(list, ","), entry = String.trim(entry) do
        {address, prefix} =
          case String.split(entry, "/") do
            [address] -> {address, nil}
            [address, prefix] -> {address, prefix}
            _ -> invalid.(entry)
          end

        ip =
          case :inet.parse_strict_address(String.to_charlist(address)) do
            {:ok, ip} -> ip
            {:error, _} -> invalid.(entry)
          end

        bits = if tuple_size(ip) == 4, do: 32, else: 128

        case prefix && Integer.parse(prefix) do
          nil -> {ip, bits}
          {length, ""} when length in 0..bits//1 -> {ip, length}
          _ -> invalid.(entry)
        end
      end

    config :idejo, :trusted_proxies, proxies
end

if config_env() == :prod do
  # TP-12: uploaded images, on local disk (the Compose volume).
  config :idejo, :uploads_dir, System.get_env("IDEJO_UPLOADS_DIR", "/data/uploads")
  # AD-05: nightly backups, on local disk (the Compose volume).
  config :idejo, :backup_dir, System.get_env("IDEJO_BACKUP_DIR", "/data/backups")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  # Empty counts as unset: the bundled Compose file passes POOL_SIZE through as it is.
  pool_size =
    case System.get_env("POOL_SIZE", "") |> String.trim() do
      "" -> 10
      size -> String.to_integer(size)
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :idejo, Idejo.Repo,
    # ssl: true,
    url: database_url,
    pool_size: pool_size,
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # AD-13: the public host name, required: links, emails, cookies and the WebSocket origin
  # check all follow it, so a wrong default would be worse than not starting.
  host =
    case System.get_env("PHX_HOST", "") |> String.trim() do
      "" ->
        raise """
        environment variable PHX_HOST is missing.
        Set it to the server's public host name, for example forum.example.org
        (no https://, no path). The bundled Compose file sets it from IDEJO_DOMAIN.
        """

      host ->
        host
    end

  config :idejo, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :idejo, :base_uri, "https://#{host}"
  # AD-08: email goes through the SMTP server set in the admin panel (Idejo.Mailer).
  config :idejo, Idejo.Mailer, adapter: Swoosh.Adapters.SMTP

  # AD-13: an SMTP server from the environment, used only while Admin → Email has no SMTP
  # host; once the panel has one, the panel's settings are used and these are not. They are
  # never stored, shown or audited.
  smtp_env = fn name ->
    case System.get_env("IDEJO_SMTP_" <> name, "") |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  if smtp_host = smtp_env.("HOST") do
    smtp_port =
      case Integer.parse(smtp_env.("PORT") || "587") do
        {port, ""} when port in 1..65_535 -> port
        _ -> raise "environment variable IDEJO_SMTP_PORT must be a port number (1 to 65535)."
      end

    smtp_security = smtp_env.("SECURITY") || if(smtp_port == 465, do: "tls", else: "starttls")

    if smtp_security not in ~w(starttls tls none) do
      raise "environment variable IDEJO_SMTP_SECURITY must be starttls, tls or none."
    end

    config :idejo, :smtp_environment,
      host: smtp_host,
      port: smtp_port,
      security: smtp_security,
      username: smtp_env.("USERNAME") || "",
      password: smtp_env.("PASSWORD") || "",
      from: smtp_env.("FROM")
  end

  config :idejo, IdejoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base,
    # AD-13: LiveView's WebSocket and long-poll connections only from this host's pages.
    check_origin: ["https://#{host}"]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :idejo, IdejoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :idejo, IdejoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :idejo, Idejo.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
