# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Community do
  @moduledoc """
  The community menu (steward decision, 2026-11-06): for an install that belongs to a group of
  communities sharing one sign-in, the forum's icon opens a menu of the member's other
  communities and a link to a directory of all of them. Optional and generic: unset on a
  standalone install, where the icon stays a link home.

  `IDEJO_COMMUNITY_URL` (`config :idejo, :community, url:`) answers which communities a
  person joined: `GET <url>?subject=<their subject at the provider>`, authenticated with this
  server's OpenID Connect client id and secret (HTTP Basic), answering
  `{"communities": [{"name": …, "url": …}]}`. Only members linked to the provider (AC-09)
  have a subject; for others the list is empty. Answers are kept for five minutes per
  member; a slow or failed answer gives an empty list, never an error on the page.
  `IDEJO_COMMUNITY_DIRECTORY_URL` (`directory_url:`) is the public directory.

  `&forum` links (steward request, 2026-11-13; `forums/2`): a message names one of the
  author's communities by its address's first label (`&garden` for
  `https://garden.idejo.org/`), linked only when the directory lists it publicly
  (`GET <directory>/api/forums?q=<host>`, its answer kept five minutes per host, a failure as
  not listed).
  """

  import Ecto.Query

  alias Idejo.Accounts.{OIDC, OIDCRegistry, User, UserIdentity}
  alias Idejo.Repo

  @table __MODULE__
  @ttl :timer.minutes(5)

  @doc "Whether the forum's icon opens the community menu."
  @spec menu?() :: boolean()
  def menu?, do: directory_url() != nil or url() != nil

  @doc """
  Whether `user` is a signed-in member not linked to the OpenID Connect provider (AC-09):
  they have no list of other communities until they link it (steward decision, 2026-11-06).
  False for visitors and without the provider.
  """
  @spec unlinked?(User.t() | nil) :: boolean()
  def unlinked?(nil), do: false

  def unlinked?(%User{} = user) do
    case OIDC.config() do
      oidc when is_list(oidc) -> subject(user, oidc[:issuer]) == nil
      _ -> false
    end
  end

  @doc """
  Where the menu may load the other communities' logos from (steward request, 2026-11-06):
  `https://*.<domain>` when the directory is at `https://<name>.<domain>/` with `<domain>`
  of two labels or more (a group's forums share its domain), else nil. For the content
  security policy's `img-src`.
  """
  @spec logo_source() :: String.t() | nil
  def logo_source do
    with "https://" <> _ = url <- directory_url(),
         %URI{host: host} when is_binary(host) <- URI.parse(url),
         [_name | domain] when length(domain) >= 2 <- String.split(host, ".") do
      "https://*." <> Enum.join(domain, ".")
    else
      _ -> nil
    end
  end

  @doc "The public directory of the communities, or nil."
  @spec directory_url() :: String.t() | nil
  def directory_url,
    do: config(:directory_url) || OIDCRegistry.config()[:directory_url]

  @doc """
  The other communities `user` joined: `[%{name:, url:}]`, empty when none can be asked.
  """
  @spec communities(User.t() | nil) :: [%{name: String.t(), url: String.t()}]
  def communities(nil), do: []

  def communities(%User{id: id} = user) do
    with url when is_binary(url) <- url(),
         oidc when is_list(oidc) <- OIDC.config(),
         subject when is_binary(subject) <- subject(user, oidc[:issuer]) do
      cached(id, fn -> fetch(url, subject, oidc) end)
    else
      _ -> []
    end
  end

  @typedoc "A forum a member may link with `&slug`."
  @type forum_link :: %{slug: String.t(), name: String.t(), url: String.t(), host: String.t()}

  @doc """
  The communities `user` joined that the directory lists publicly, for `&forum` links: all
  of them (`:all`), or those whose slug is among `slugs`, matching `query` by slug or name
  (`query:`), at most `limit:`. A slug is the forum address's first label, lowercased; two
  communities with the same one give the first.
  """
  @spec forums(User.t() | nil, [String.t()] | :all, keyword()) :: [forum_link()]
  def forums(user, slugs, opts \\ [])
  def forums(nil, _slugs, _opts), do: []
  def forums(_user, [], _opts), do: []

  def forums(%User{} = user, slugs, opts) do
    query = opts |> Keyword.get(:query, "") |> String.downcase()

    user
    |> communities()
    |> Enum.flat_map(&forum_link/1)
    |> Enum.uniq_by(& &1.slug)
    |> Enum.filter(&((slugs == :all or &1.slug in slugs) and matches?(&1, query)))
    |> Enum.take(Keyword.get(opts, :limit, 50))
    |> Enum.filter(&listed?(&1.host))
  end

  defp matches?(_forum, ""), do: true

  defp matches?(forum, query) do
    String.starts_with?(forum.slug, query) or
      String.starts_with?(String.downcase(forum.name), query)
  end

  defp forum_link(%{name: name, url: url}) do
    with %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) <- URI.parse(url),
         host = String.downcase(host),
         [slug | _] <- String.split(host, "."),
         true <- Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug) do
      [%{slug: slug, name: name, url: "https://" <> host <> "/", host: host}]
    else
      _ -> []
    end
  end

  # Whether the public directory lists the forum at `host`.
  defp listed?(host) do
    case directory_url() do
      "http" <> _ = directory -> cached({:listed, host}, fn -> ask_listed(directory, host) end)
      _ -> false
    end
  end

  defp ask_listed(directory, host) do
    request =
      Req.new(
        url: String.trim_trailing(directory, "/") <> "/api/forums",
        params: [q: host],
        receive_timeout: 2_000,
        connect_options: [timeout: 2_000],
        retry: false,
        redirect: false
      )
      |> Req.merge(Application.get_env(:idejo, :community_req_options, []))

    case Req.get(request) do
      {:ok, %{status: 200, body: %{"forums" => forums}}} when is_list(forums) ->
        Enum.any?(forums, fn
          %{"url" => url} when is_binary(url) -> URI.parse(url).host == host
          _ -> false
        end)

      _ ->
        false
    end
  end

  @doc false
  # The cache, an ETS table owned by the application's process tree.
  def child_spec(_arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  @doc false
  def start_link do
    Agent.start_link(
      fn -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true]) end,
      name: __MODULE__
    )
  end

  defp subject(user, issuer) do
    Repo.one(
      from i in UserIdentity,
        where: i.user_id == ^user.id and i.issuer == ^issuer,
        select: i.subject,
        limit: 1
    )
  end

  defp cached(id, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, id) do
      [{^id, list, at}] when now - at < @ttl ->
        list

      _ ->
        list = fun.()
        :ets.insert(@table, {id, list, now})
        list
    end
  rescue
    # No cache table (a test, or the tree not started): ask every time.
    ArgumentError -> fun.()
  end

  defp fetch(url, subject, oidc) do
    request =
      Req.new(
        url: url,
        params: [subject: subject],
        auth: {:basic, oidc[:client_id] <> ":" <> oidc[:client_secret]},
        receive_timeout: 2_000,
        connect_options: [timeout: 2_000],
        retry: false
      )
      |> Req.merge(Application.get_env(:idejo, :community_req_options, []))

    case Req.get(request) do
      {:ok, %{status: 200, body: %{"communities" => list}}} when is_list(list) ->
        for %{"name" => name, "url" => "http" <> _ = link} <- list,
            is_binary(name) and name != "",
            do: %{name: String.slice(name, 0, 100), url: link}

      _ ->
        []
    end
  end

  defp url, do: config(:url)
  defp config(key), do: (Application.get_env(:idejo, :community) || [])[key]
end
