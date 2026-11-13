# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Inbox do
  @moduledoc """
  Inbox mode (steward request, 2026-11-10): `IDEJO_INBOX=on` makes this install the inbox of
  a group of communities sharing one sign-in (the community menu's, `Idejo.Community`): one
  page per member, with idejo's own look, header, menus, composer and topic lists, but no
  sidebar and no categories of its own. It answers the group's chat service
  (`Idejo.Community.Chat`): the forums' `IDEJO_CHAT_URL` and `IDEJO_TOPICS_URL` point here.

    * **Forums** (`/`): the communities the member joined (`Idejo.Community.communities/1`).
    * **Topics** (`/topics`): the topics they follow in each, as idejo's topic rows, compact
      or expanded (`topics/1`, `Idejo.Inbox.RemoteTopic`).
    * **Chats** (`/chat`, `/p/{id}`): idejo's private conversations, between members known
      here by their provider subject. Someone named by a forum's "Private Message"
      (`/chat/new?with=<subject>`) gets an account here at once (`member/1`), linked to that
      subject, which their own sign-in later finds. Their conversations in the forums are
      copied here (`import/1`).

  Everything about other forums goes through the group's service at `IDEJO_COMMUNITY_URL`
  (`<url>/inbox/...`), with this server's OpenID Connect client id and secret (HTTP Basic):
  it asks the forums, through their chat service interface, and answers here. The service
  asks back how many chats have something new
  (`GET /community/inbox-unread?subject=`), proving itself
  with the same credentials (`service?/1`). Without `IDEJO_INBOX`, nothing here runs.
  """

  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDC, User, UserIdentity}
  alias Idejo.Community.{Profile, SharedSettings}
  alias Idejo.{Conversations, Federation, Repo}
  alias Idejo.Forum.Topic
  alias Idejo.Inbox.RemoteTopic
  alias Idejo.Messages.{Message, Reaction}

  @import_every :timer.hours(1)

  @doc "Whether this install is a group's inbox."
  @spec on?() :: boolean()
  def on?, do: Application.get_env(:idejo, :inbox, false) == true

  @doc "The group's service, or nil."
  @spec service_url() :: String.t() | nil
  def service_url do
    case (Application.get_env(:idejo, :community) || [])[:url] do
      "http" <> _ = url -> String.trim_trailing(url, "/") <> "/inbox"
      _ -> nil
    end
  end

  @doc "Whether a request's HTTP Basic credentials are this server's own client's."
  @spec service?({String.t(), String.t()} | :error) :: boolean()
  def service?({id, secret}) when is_binary(id) and is_binary(secret) do
    case OIDC.config() do
      oidc when is_list(oidc) ->
        Plug.Crypto.secure_compare(id, oidc[:client_id] || "") and
          Plug.Crypto.secure_compare(secret, oidc[:client_secret] || "")

      _ ->
        false
    end
  end

  def service?(_credentials), do: false

  ## Members

  @doc "The member linked to `subject` at the provider, or nil."
  @spec find_member(String.t()) :: User.t() | nil
  def find_member(subject) when is_binary(subject) do
    with oidc when is_list(oidc) <- OIDC.config() do
      issuer = oidc[:issuer]

      Repo.one(
        from u in User,
          join: i in UserIdentity,
          on: i.user_id == u.id,
          where: i.issuer == ^issuer and i.subject == ^subject
      )
    end
  end

  @doc """
  The member linked to `subject`, made when there is none (someone a forum's "Private
  Message" names before they ever came here): their idejo ID's username and picture
  (`Idejo.Community.Profile`), an address nobody receives mail at until they sign in
  (`claim/2`), verified, welcomed. `{:error, :unknown}` when the provider has no such person.
  """
  @spec member(String.t()) :: {:ok, User.t()} | {:error, :unknown | Ecto.Changeset.t()}
  def member(subject) when is_binary(subject) and subject != "" do
    case find_member(subject) do
      %User{} = user -> {:ok, user}
      nil -> new_member(subject)
    end
  end

  def member(_subject), do: {:error, :unknown}

  defp new_member(subject) do
    with oidc when is_list(oidc) <- OIDC.config(),
         %{username: username} = profile when is_binary(username) <- Profile.fetch(subject),
         attrs = %{
           "email" => "#{Ecto.UUID.generate()}@inbox.invalid",
           "username" => Accounts.free_username(username),
           "display_name" => String.slice(username, 0, 60),
           "password" => 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64()
         },
         {:ok, user} <- Repo.transact(fn -> register(attrs, oidc[:issuer], subject) end) do
      Profile.adopt_picture(user, profile)
      {:ok, Repo.get!(User, user.id)}
    else
      {:error, %Ecto.Changeset{}} = error -> error
      _ -> {:error, :unknown}
    end
  end

  defp register(attrs, issuer, subject) do
    with {:ok, user} <-
           Accounts.register_user(attrs, confirmed: true, welcomed: true, skip_invite: true),
         {:ok, _} <-
           %{user_id: user.id, issuer: issuer, subject: subject}
           |> UserIdentity.changeset()
           |> Repo.insert() do
      {:ok, user}
    end
  end

  @doc """
  At a member's sign-in: an account made for them before (`member/1`) takes the email the
  provider gives, verified as the provider says.
  """
  @spec claim(User.t(), map()) :: User.t()
  def claim(%User{email: email} = user, %{"email" => new} = claims)
      when is_binary(new) and new != "" do
    if on?() and String.ends_with?(email, "@inbox.invalid") and
         Accounts.get_user_by_email(new) == nil do
      verified? = claims["email_verified"] in [true, "true"]

      user
      |> Ecto.Changeset.change(email: new)
      |> then(&if(verified?, do: &1, else: Ecto.Changeset.change(&1, confirmed_at: nil)))
      |> Repo.update()
      |> case do
        {:ok, user} -> user
        _ -> user
      end
    else
      user
    end
  end

  def claim(user, _claims), do: user

  @doc "How many of `subject`'s conversations have something new (0 for someone unknown)."
  @spec unread(String.t()) :: non_neg_integer()
  def unread(subject) do
    case find_member(subject) do
      %User{} = user -> Conversations.unread_count(user)
      nil -> 0
    end
  end

  ## Topics

  @doc """
  The topics `user` follows in the group's forums, the latest active first:
  `[%{topic:, preview:, unread:, base:, forum:}]` (`Idejo.Inbox.RemoteTopic`), `base` the
  forum's address their links start with.
  """
  @spec topics(User.t()) :: [map()]
  def topics(%User{} = user) do
    with subject when is_binary(subject) <- subject(user),
         {:ok, %{"forums" => forums}} when is_list(forums) <-
           ask(:get, "/topics", params: [subject: subject], receive_timeout: 8_000) do
      for %{"url" => "http" <> _ = url, "topics" => topics} = forum <- forums,
          is_list(topics),
          topic <- topics,
          entry = RemoteTopic.from_json(topic, url, forum["name"]),
          entry != nil do
        entry
      end
      |> Enum.sort_by(& &1.topic.last_activity_at, {:desc, DateTime})
    else
      _ -> []
    end
  end

  ## Settings for all forums

  @doc """
  Whether `user` can save settings for all their forums here (steward request, 2026-11-13):
  inbox mode, and linked to the provider.
  """
  @spec everywhere?(User.t() | nil) :: boolean()
  def everywhere?(%User{} = user), do: on?() and service_url() != nil and subject(user) != nil
  def everywhere?(_user), do: false

  @doc """
  Saves `user`'s `sections` (`Idejo.Community.SharedSettings`) on every forum they joined,
  through the group's service, `POST <service>/settings` `{subject, settings}` →
  `{"forums": [{"name", "host", "answered", "saved", "failed"}]}`. `shared:` also sets
  whether their notification choices are shared. `{:ok, %{done: [name], missed: [name]}}`,
  a forum missed when it did not answer (an idejo before 0.3.7, or down) or did not take a
  section; `:error` when the service did not answer.
  """
  @spec save_everywhere(User.t(), [String.t()], keyword()) ::
          {:ok, %{done: [String.t()], missed: [String.t()]}} | :error
  def save_everywhere(%User{} = user, sections, opts \\ []) do
    settings = SharedSettings.export(user, sections, Keyword.take(opts, [:shared]))

    with subject when is_binary(subject) <- subject(user),
         {:ok, %{"forums" => forums}} when is_list(forums) <-
           ask(:post, "/settings",
             json: %{subject: subject, settings: settings},
             receive_timeout: 15_000
           ) do
      {done, missed} =
        forums
        |> Enum.filter(&(is_map(&1) and is_binary(&1["name"])))
        |> Enum.split_with(&(&1["answered"] == true and &1["failed"] in [nil, []]))

      {:ok, %{done: Enum.map(done, & &1["name"]), missed: Enum.map(missed, & &1["name"])}}
    else
      _ -> :error
    end
  end

  ## Copies of the forums' private conversations

  @doc """
  Copies `user`'s private conversations from the group's forums, at most once an hour
  (`force: true` asks anyway): `%{copied:, remaining: [%{name:, url:, count:}]}`, the
  conversations that stayed in a forum (someone there has no idejo ID).
  """
  @spec import(User.t(), keyword()) :: %{copied: non_neg_integer(), remaining: [map()]}
  def import(%User{} = user, opts \\ []) do
    now = System.monotonic_time(:millisecond)

    case lookup(user.id) do
      {at, remaining} when now - at < @import_every ->
        if opts[:force], do: do_import(user, now), else: %{copied: 0, remaining: remaining}

      _ ->
        do_import(user, now)
    end
  end

  @doc false
  # When each member's conversations were last copied, in an ETS table of the tree.
  def child_spec(_arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc false
  def start_link do
    Agent.start_link(
      fn -> :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true]) end,
      name: __MODULE__
    )
  end

  defp lookup(user_id) do
    case :ets.lookup(__MODULE__, user_id) do
      [{^user_id, at, remaining}] -> {at, remaining}
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp remember(user_id, now, remaining) do
    :ets.insert(__MODULE__, {user_id, now, remaining})
  rescue
    ArgumentError -> true
  end

  defp do_import(user, now) do
    with subject when is_binary(subject) <- subject(user),
         {:ok, %{"forums" => forums}} when is_list(forums) <-
           ask(:get, "/conversations", params: [subject: subject], receive_timeout: 10_000) do
      results =
        for %{"host" => host} = forum <- forums, is_binary(host), do: copy_forum(subject, forum)

      remaining = for {_, %{count: n} = r} <- results, n > 0, do: r
      remember(user.id, now, remaining)
      %{copied: results |> Enum.map(&elem(&1, 0)) |> Enum.sum(), remaining: remaining}
    else
      _ -> %{copied: 0, remaining: []}
    end
  end

  defp copy_forum(subject, %{"host" => host} = forum) do
    copied =
      for %{"id" => id} = conversation <- forum["conversations"] || [],
          {:ok, _} <- [copy(host, conversation)],
          do: id

    if copied != [],
      do: ask(:post, "/conversations/moved", json: %{subject: subject, host: host, ids: copied})

    {length(copied),
     %{
       name: forum["name"] || host,
       url: forum["url"],
       count: if(is_integer(forum["remaining"]), do: forum["remaining"], else: 0)
     }}
  end

  @doc """
  Copies one conversation a forum sent (`host`): its two participants' accounts here
  (`member/1`), their conversation (`Conversations`), and each message once
  (`messages.import_source`), closed, at its own time, with its reactions. Its HTML is the
  forum's, sanitised again.
  """
  @spec copy(String.t(), map()) :: {:ok, Topic.t()} | {:error, term()}
  def copy(host, %{"subjects" => [a, b], "messages" => messages})
      when is_binary(a) and is_binary(b) and a != b and is_list(messages) do
    with {:ok, user_a} <- member(a),
         {:ok, user_b} <- member(b),
         {:ok, topic} <- Conversations.pair(user_a, user_b) do
      users = %{a => user_a, b => user_b}

      Repo.transact(fn -> copy_messages(host, topic, users, messages) end)
    end
  end

  def copy(_host, _conversation), do: {:error, :unsupported}

  defp copy_messages(host, topic, users, messages) do
    latest =
      messages
      |> Enum.map(&copy_message(host, topic, users, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    if latest, do: caught_up(topic, latest)
    {:ok, topic}
  end

  # The conversation counts its copied messages and is as recent as the newest.
  defp caught_up(topic, latest) do
    count =
      Repo.aggregate(
        from(m in Message, where: m.topic_id == ^topic.id and is_nil(m.deleted_at)),
        :count
      )

    Repo.update_all(from(t in Topic, where: t.id == ^topic.id), set: [message_count: count])

    Repo.update_all(
      from(t in Topic, where: t.id == ^topic.id and t.last_activity_at < ^latest),
      set: [last_activity_at: latest]
    )
  end

  defp copy_message(host, topic, users, %{"id" => id, "author" => author} = m) do
    source = host <> "/" <> to_string(id)

    with %User{} = user <- users[author],
         {:ok, at, _} <- DateTime.from_iso8601(to_string(m["opened_at"])),
         false <- Repo.exists?(from x in Message, where: x.import_source == ^source) do
      at = %{at | microsecond: {elem(at.microsecond, 0), 6}}
      message_id = Federation.generate_id()

      Repo.insert!(%Message{
        id: message_id,
        uri: Federation.uri(:message, message_id),
        topic_id: topic.id,
        author_id: user.id,
        state: "closed",
        opened_at: at,
        closes_at: at,
        closed_at: at,
        body_md: to_string(m["body_md"]),
        body_html: sanitize(m["body_html"]),
        edited: m["edited"] == true,
        spoiler: m["spoiler"] == true,
        import_source: source
      })

      for %{"emoji" => emoji, "subject" => subject} <- m["reactions"] || [],
          is_binary(emoji),
          %User{} = reactor <- [users[subject]] do
        Repo.insert(%Reaction{message_id: message_id, user_id: reactor.id, emoji: emoji},
          on_conflict: :nothing
        )
      end

      at
    else
      _ -> nil
    end
  end

  defp sanitize(nil), do: ""

  defp sanitize(html) when is_binary(html),
    do: MDEx.safe_html(html, escape: [:curly_braces_in_code])

  defp sanitize(_html), do: ""

  ## The group's service

  defp subject(user) do
    case OIDC.config() do
      oidc when is_list(oidc) ->
        Repo.one(
          from i in UserIdentity,
            where: i.user_id == ^user.id and i.issuer == ^oidc[:issuer],
            select: i.subject,
            limit: 1
        )

      _ ->
        nil
    end
  end

  defp ask(method, path, opts) do
    with url when is_binary(url) <- service_url(),
         oidc when is_list(oidc) <- OIDC.config() do
      request =
        [
          method: method,
          url: url <> path,
          auth: {:basic, oidc[:client_id] <> ":" <> oidc[:client_secret]},
          connect_options: [timeout: 2_000],
          retry: false
        ]
        |> Keyword.merge(opts)
        |> Req.new()
        |> Req.merge(Application.get_env(:idejo, :community_req_options, []))

      case Req.request(request) do
        {:ok, %{status: 200, body: %{} = body}} -> {:ok, body}
        _ -> :error
      end
    else
      _ -> :error
    end
  end
end
