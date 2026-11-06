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
  """

  import Ecto.Query

  alias Idejo.Accounts.{User, UserIdentity}
  alias Idejo.Repo

  @table __MODULE__
  @ttl :timer.minutes(5)

  @doc "Whether the forum's icon opens the community menu."
  @spec menu?() :: boolean()
  def menu?, do: directory_url() != nil or url() != nil

  @doc "The public directory of the communities, or nil."
  @spec directory_url() :: String.t() | nil
  def directory_url, do: config(:directory_url)

  @doc """
  The other communities `user` joined: `[%{name:, url:}]`, empty when none can be asked.
  """
  @spec communities(User.t() | nil) :: [%{name: String.t(), url: String.t()}]
  def communities(nil), do: []

  def communities(%User{id: id} = user) do
    with url when is_binary(url) <- url(),
         oidc when is_list(oidc) <- Application.get_env(:idejo, :oidc),
         subject when is_binary(subject) <- subject(user, oidc[:issuer]) do
      cached(id, fn -> fetch(url, subject, oidc) end)
    else
      _ -> []
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
