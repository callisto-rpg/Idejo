# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Payload do
  @moduledoc """
  What a push says (PN-01 to PN-03, PN-12): Declarative Web Push JSON,
  `%{"web_push" => 8030, "notification" => %{"title", "body", "navigate", "tag", "lang"},
  "app_badge" => n}`, as the service worker (`priv/push/sw.js`) reads it.

    * reply (PN-01): "{name} replied in {topic}", the reply's excerpt, its permalink; with
      several unread replies in the topic, "{N} replies in {topic}". Tag `reply-{topic id}`.
    * mention (PN-02): "{name} mentioned you in {topic}", the excerpt, the permalink; with
      several unread, "You have been mentioned {N} times", up to three topic titles, the
      Unread page. Tag `mentions`; urgency `high`.
    * role_mention (PN-03): "{name} mentioned +{role} in {topic}", or "Your role has been
      tagged {N} times". Tag `role-mentions`.
    * private (steward decision, 2026-10-27): "{name} sent you a private message", the
      excerpt, the permalink; with several unread private messages, "{N} new private
      messages.", the names of up to three people waiting for an answer, the Private
      Conversations page. Tag `private`; urgency `high`. N counts unread messages in the
      user's private conversations (`Idejo.Conversations.unread_summary/1`).
    * followed activity (PN-04, `followed/2`): "There are new messages in {N} topics you
      follow", the Unread page. Tag `followed`.

  N counts the user's unread notifications of that kind (`Idejo.Reading.unread_notified/3`):
  reading them resets it. Nothing is built when there is nothing unread any more. The badge
  is the user's unread replies and mentions (`Idejo.Reading.for_you/1`). Texts are in the
  server's language.

  Changes to this module get an extra careful human review (DV-06).
  """
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Markdown
  alias Idejo.Messages.Message
  alias Idejo.Reading

  @excerpt 120

  @doc """
  The payload and urgency of a push of `kind` to `user` about `message` (its author and
  topic loaded), or `:nothing_unread`.
  """
  @spec build(User.t(), Message.t(), String.t()) ::
          {:ok, map(), String.t()} | {:error, :nothing_unread}
  def build(%User{} = user, %Message{} = message, "private") do
    case Idejo.Conversations.unread_summary(user) do
      %{count: 0} -> {:error, :nothing_unread}
      unread -> {:ok, payload(user, private_text(unread, message), "private"), "high"}
    end
  end

  def build(%User{} = user, %Message{} = message, kind)
      when kind in ~w(reply mention role_mention) do
    topic_id = if kind == "reply", do: message.topic_id
    unread = Reading.unread_notified(user, kind, topic_id)

    if unread.count == 0 do
      {:error, :nothing_unread}
    else
      payload = payload(user, text(kind, unread, user, message), tag(kind, message))
      {:ok, payload, if(kind == "mention", do: "high", else: "normal")}
    end
  end

  defp payload(user, {title, body, navigate}, tag) do
    %{
      "web_push" => 8030,
      "notification" => %{
        "title" => title,
        "body" => body,
        "navigate" => navigate,
        "tag" => tag,
        "lang" => Gettext.get_locale(IdejoWeb.Gettext)
      },
      "app_badge" => Reading.for_you(user).count
    }
  end

  defp private_text(%{count: 1}, message) do
    {gettext("%{name} sent you a private message", name: message.author.display_name),
     excerpt(message), permalink(message)}
  end

  defp private_text(%{count: count, names: names}, _message) do
    {ngettext("1 new private message.", "%{count} new private messages.", count),
     Enum.join(names, " · "), Application.fetch_env!(:idejo, :base_uri) <> "/p"}
  end

  defp text("reply", %{count: 1}, _user, message) do
    {gettext("%{name} replied in %{topic}",
       name: message.author.display_name,
       topic: message.topic.title
     ), excerpt(message), permalink(message)}
  end

  defp text("reply", %{count: count}, _user, message) do
    {gettext("%{count} replies in %{topic}", count: count, topic: message.topic.title),
     excerpt(message), permalink(message)}
  end

  defp text("mention", %{count: 1}, _user, message) do
    {gettext("%{name} mentioned you in %{topic}",
       name: message.author.display_name,
       topic: message.topic.title
     ), excerpt(message), permalink(message)}
  end

  defp text("mention", %{count: count, titles: titles}, _user, _message) do
    {gettext("You have been mentioned %{count} times", count: count), Enum.join(titles, " · "),
     unread_page()}
  end

  defp text("role_mention", %{count: 1}, user, message) do
    {gettext("%{name} mentioned +%{role} in %{topic}",
       name: message.author.display_name,
       role: role_mentioned(user, message),
       topic: message.topic.title
     ), excerpt(message), permalink(message)}
  end

  defp text("role_mention", %{count: count, titles: titles}, _user, _message) do
    {gettext("Your role has been tagged %{count} times", count: count), Enum.join(titles, " · "),
     unread_page()}
  end

  # The highest-ranked of the user's roles the message +mentions, as it is typed.
  defp role_mentioned(user, message) do
    slugs = for {:role, slug} <- Markdown.references(message.body_md), do: slug

    user
    |> Access.roles_of()
    |> Enum.map(&Access.role_slug/1)
    |> Enum.find(hd(slugs ++ [""]), &(&1 in slugs))
  end

  @doc """
  The payload of a followed-activity push (PN-04): "There are new messages in {N} topics you
  follow", no excerpt, the Unread page. Tag `followed`.
  """
  @spec followed(User.t(), pos_integer()) :: map()
  def followed(%User{} = user, count) do
    %{
      "web_push" => 8030,
      "notification" => %{
        "title" =>
          ngettext(
            "There are new messages in 1 topic you follow",
            "There are new messages in %{count} topics you follow",
            count
          ),
        "body" => "",
        "navigate" => unread_page(),
        "tag" => "followed",
        "lang" => Gettext.get_locale(IdejoWeb.Gettext)
      },
      "app_badge" => Reading.for_you(user).count
    }
  end

  @doc "The payload of \"Send test notification\" (PN-24): it opens the profile page."
  @spec test(User.t()) :: map()
  def test(%User{} = user) do
    %{
      "web_push" => 8030,
      "notification" => %{
        "title" => gettext("Test notification"),
        "body" => gettext("Notifications from this server work on this device."),
        "navigate" => Application.fetch_env!(:idejo, :base_uri) <> "/users/settings",
        "tag" => "test",
        "lang" => Gettext.get_locale(IdejoWeb.Gettext)
      },
      "app_badge" => Reading.for_you(user).count
    }
  end

  defp tag("reply", message), do: "reply-" <> message.topic_id
  defp tag("mention", _message), do: "mentions"
  defp tag("role_mention", _message), do: "role-mentions"

  @doc "A message's text for a push: plain, at most #{@excerpt} characters, then “…”."
  @spec excerpt(Message.t()) :: String.t()
  def excerpt(%Message{} = message), do: Forum.excerpt(message, @excerpt)

  defp permalink(message), do: Federation.uri(:message, message.id)

  defp unread_page, do: Application.fetch_env!(:idejo, :base_uri) <> "/unread"
end
