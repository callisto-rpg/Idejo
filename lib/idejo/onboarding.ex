# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Onboarding do
  @moduledoc """
  Onboarding (steward request, 2026-11-22), set in **Admin → Onboarding and information**.

  The **onboarding topic** (`onboarding_topic_id`): one topic of the forum, chosen by an
  administrator among its topics, whose category, icon and title they edit there. It is
  always topical and followed by everyone (`Forum.make_topical/3`, `Forum.set_autofollow/3`),
  and nobody deletes or archives it while it is the onboarding topic
  (`Forum.delete_topic/3`, `Forum.archive_topic/3` and `Forum.delete_category/3` with
  `topics: :archive` answer `{:error, :onboarding}`). When there is none (never set, or its
  topic gone), `ensure/0` starts the default: **Welcome**, in the first category, with the
  waving hand icon (bundled, `priv/onboarding/waving_hand.png`, added to the topic icons when
  missing), started by the server account `idejo`
  (`Idejo.Messages.Automessages.server_account/1`). It runs at boot and after a category is
  made, unless `:onboarding_auto` is off (tests), and when the admin page opens.

  The **new user presentation question** (`onboarding_question`, `{onboarding.string.1}`):
  text the administrator writes, read with `string/1`.

  The **tour** (steward request, 2026-11-22; `IdejoWeb.OnboardingComponents`): a member who
  has closed the welcome card and not finished it yet (`touring?/1`, `users.onboarded_at`)
  is led to the onboarding topic when they may post there (`tour_topic/1`). Step 1, on any
  other page: its link in the sidebar. On its page (`topic_step/2`): 2, before their first
  message there; 3, while it is open; 4, once it closed, which finishes the tour
  (`Idejo.Accounts.mark_onboarded/1`).
  """
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.Forum
  alias Idejo.Forum.{Category, Topic, TopicIcon, TopicIcons}
  alias Idejo.Messages.Automessages
  alias Idejo.Messages.Message
  alias Idejo.Repo
  alias Idejo.Settings

  @title "Welcome"
  @icon_name "Waving hand"
  @icon_path "priv/onboarding/waving_hand.png"

  @doc "The onboarding topic's id, or nil when none is set."
  @spec topic_id() :: String.t() | nil
  def topic_id do
    case Settings.get(:onboarding_topic_id) do
      "" -> nil
      id -> id
    end
  end

  @doc "Whether `topic` is the onboarding topic."
  @spec onboarding_topic?(Topic.t() | String.t() | nil) :: boolean()
  def onboarding_topic?(%Topic{id: id}), do: onboarding_topic?(id)
  def onboarding_topic?(id) when is_binary(id), do: id == topic_id()
  def onboarding_topic?(nil), do: false

  @doc "The onboarding topic, with its category and icon, or nil when there is none."
  @spec topic() :: Topic.t() | nil
  def topic do
    with id when is_binary(id) <- topic_id(),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Topic{} = topic <- Repo.get(Topic, id) do
      Repo.preload(topic, [:category, icon: :upload])
    else
      _ -> nil
    end
  end

  @doc """
  Onboarding's texts by number, as `{onboarding.string.N}` names them: 1 is the new user
  presentation question.
  """
  @spec string(pos_integer()) :: String.t()
  def string(1), do: Settings.get(:onboarding_question)

  @doc """
  The onboarding topic, started as the default when there is none and a category exists
  (`{:error, :no_category}` while there is none).
  """
  @spec ensure() :: {:ok, Topic.t()} | {:error, term()}
  def ensure do
    case topic() do
      %Topic{} = topic -> {:ok, topic}
      nil -> start_default()
    end
  end

  @doc "`ensure/0`, unless `:onboarding_auto` is off (tests start it themselves)."
  @spec ensure_auto() :: :ok
  def ensure_auto do
    if Application.get_env(:idejo, :onboarding_auto, true), do: ensure()
    :ok
  end

  defp start_default do
    with %Category{} = category <- first_category() || {:error, :no_category},
         {:ok, sender} <- Automessages.server_account(Automessages.default_username()),
         {:ok, icon} <- default_icon(sender),
         {:ok, topic} <-
           Forum.create_server_topic(sender, category, %{
             title: @title,
             body: welcome_text(),
             icon_id: icon.id
           }),
         {:ok, _} <- Settings.update_settings(nil, %{"onboarding_topic_id" => topic.id}) do
      {:ok, Repo.preload(topic, [:category, icon: :upload], force: true)}
    end
  end

  defp welcome_text do
    "Welcome to #{Settings.get(:server_name)}! Introduce yourself here."
  end

  # The first category in the home page's order, never the Archive.
  defp first_category do
    Repo.one(
      from c in Category,
        where: not c.archive,
        order_by: [asc: c.position, asc: c.name],
        limit: 1
    )
  end

  @doc """
  The waving hand among the topic icons, added from the bundled image when it is not there
  (by `user`, a server account or an administrator).
  """
  @spec default_icon(User.t()) :: {:ok, TopicIcon.t()} | {:error, term()}
  def default_icon(%User{} = user) do
    case Repo.one(from i in TopicIcon, where: i.name == @icon_name, limit: 1) do
      %TopicIcon{} = icon -> {:ok, Repo.preload(icon, :upload)}
      nil -> TopicIcons.add_bundled(user, Application.app_dir(:idejo, @icon_path), @icon_name)
    end
  end

  @doc """
  Topics an administrator may choose as the onboarding topic, by title: neither private nor
  archived, eight at most, the most active first.
  """
  @spec search(String.t()) :: [Topic.t()]
  def search(query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      []
    else
      pattern = "%" <> String.replace(query, ~w(\\ % _), &("\\" <> &1)) <> "%"

      Repo.all(
        from t in Topic,
          where: not t.private and t.state != "archived" and ilike(t.title, ^pattern),
          order_by: [desc: t.last_activity_at],
          limit: 8,
          preload: :category
      )
    end
  end

  @doc """
  Makes `topic` the onboarding topic, as an administrator: topical (keeping its icon, else
  the waving hand) and followed by everyone. Audited as a setting change, and each change to
  the topic as the forum's own (`topic.topical`, `topic.autofollow`).
  """
  @spec choose(User.t(), Topic.t()) :: {:ok, Topic.t()} | {:error, term()}
  def choose(%User{} = admin, %Topic{} = topic) do
    Idejo.Access.as_administrator(admin, fn ->
      with :ok <- choosable(topic),
           {:ok, topic} <- onboarding_shape(admin, topic),
           {:ok, _} <- Settings.update_settings(admin, %{"onboarding_topic_id" => topic.id}) do
        {:ok, topic()}
      end
    end)
  end

  defp choosable(%Topic{private: false, state: state}) when state != "archived", do: :ok
  defp choosable(_topic), do: {:error, :invalid_target}

  # Topical, with an icon, and followed by everyone.
  defp onboarding_shape(admin, %Topic{} = topic) do
    with {:ok, topic} <- topical(admin, topic),
         do: Forum.set_autofollow(admin, topic, true)
  end

  defp topical(_admin, %Topic{topical: true} = topic), do: {:ok, topic}

  defp topical(admin, %Topic{} = topic) do
    with {:ok, icon} <- default_icon(admin), do: Forum.make_topical(admin, topic, icon)
  end

  @doc """
  Changes the onboarding topic's category, icon and title (`"category_id"`, `"icon_id"`,
  `"title"`), as an administrator, through the moderators' own functions, each logged as
  theirs (`topic.move`, `topic.icon`, `topic.rename`). Unchanged values do nothing.
  """
  @spec update(User.t(), map()) :: {:ok, Topic.t()} | {:error, term()}
  def update(%User{} = admin, params) when is_map(params) do
    Idejo.Access.as_administrator(admin, fn ->
      with %Topic{} = topic <- topic() || {:error, :onboarding_topic},
           {:ok, topic} <- onboarding_shape(admin, topic),
           {:ok, topic} <- move(admin, topic, params["category_id"]),
           {:ok, topic} <- set_icon(admin, topic, params["icon_id"]),
           {:ok, _} <- rename(admin, topic, params["title"]) do
        {:ok, topic()}
      end
    end)
  end

  defp move(_admin, %Topic{category_id: id} = topic, id), do: {:ok, topic}
  defp move(_admin, topic, blank) when blank in [nil, ""], do: {:ok, topic}

  defp move(admin, topic, category_id) do
    case Repo.get(Category, category_id) do
      %Category{} = category -> Forum.move_topic(admin, topic, category)
      nil -> {:error, :invalid_target}
    end
  end

  defp set_icon(_admin, %Topic{icon_id: id} = topic, id), do: {:ok, topic}
  defp set_icon(_admin, topic, blank) when blank in [nil, ""], do: {:ok, topic}

  defp set_icon(admin, topic, icon_id) do
    case TopicIcons.get(icon_id) do
      %TopicIcon{} = icon -> Forum.set_topic_icon(admin, topic, icon)
      nil -> {:error, :invalid_target}
    end
  end

  defp rename(_admin, topic, nil), do: {:ok, topic}
  defp rename(admin, topic, title), do: Forum.rename_topic(admin, topic, title)

  @doc """
  Whether `user` is on the onboarding tour: a member who closed the welcome card and has not
  finished the tour.
  """
  @spec touring?(User.t() | nil) :: boolean()
  def touring?(%User{status: "active", welcomed_at: %DateTime{}, onboarded_at: nil}), do: true
  def touring?(_user), do: false

  @doc "The onboarding topic, when `user` is on the tour and may post in it; else nil."
  @spec tour_topic(User.t() | nil) :: Topic.t() | nil
  def tour_topic(user) do
    with true <- touring?(user),
         %Topic{} = topic <- topic(),
         true <- Forum.can_post?(user, topic) do
      topic
    else
      _ -> nil
    end
  end

  @doc """
  The tour's step on the onboarding topic's page: 2 before `user`'s first message there, 3
  while their last one is open, 4 once it closed.
  """
  @spec topic_step(User.t(), Topic.t()) :: 2 | 3 | 4
  def topic_step(%User{id: user_id}, %Topic{id: topic_id}) do
    last =
      Repo.one(
        from m in Message,
          where: m.topic_id == ^topic_id and m.author_id == ^user_id,
          order_by: [desc: m.opened_at, desc: m.id],
          limit: 1,
          select: m.state
      )

    case last do
      nil -> 2
      "open" -> 3
      _closed -> 4
    end
  end

  @doc "Saves the new user presentation question, as an administrator (a setting)."
  @spec save_question(User.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def save_question(%User{} = admin, text) when is_binary(text),
    do: Settings.update_settings(admin, %{"onboarding_question" => text})
end
