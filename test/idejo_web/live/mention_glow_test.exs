# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MentionGlowTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Repo

  # Steward decision, 2026-10-25: an unread message tagging the reader glows when scrolled to.
  @tag req: "TP-10"
  test "TP-10 unread messages that @mention the reader or +mention their role are marked to glow",
       %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    reader =
      user_fixture()
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    :ok = Access.grant_role(reader, crew)
    slug = Access.role_slug(crew)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    post = fn user, body ->
      {:ok, message} = Forum.post_message(user, topic, %{"body" => body})
      message
    end

    # Read already: no glow.
    read = post.(user_fixture(), "Earlier @#{reader.username}")
    :ok = Reading.mark_read(reader, topic)

    plain = post.(user_fixture(), "Count me in")
    mention = post.(user_fixture(), "Bring cake @#{reader.username} and +#{slug}")
    role = post.(user_fixture(), "Hey +#{slug}")
    own = post.(reader, "Me, @#{reader.username}")

    first = Reading.first_unread(reader, topic)
    assert first.id == plain.id

    {:ok, lv, _html} =
      conn
      |> log_in_user(reader)
      |> live_isolated(IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id, "first_unread" => first}
      )

    assert has_element?(lv, ~s(#message-#{mention.id}[data-mention-glow="mention"]))
    assert has_element?(lv, ~s(#message-#{role.id}[data-mention-glow="role-mention"]))

    for message <- [read, plain, own],
        do: refute(has_element?(lv, "#message-#{message.id}[data-mention-glow]"))

    # The tags that pulse: the reader's own link and their roles'.
    tags =
      ~s(["/u/#{reader.id}","/r/#{slug}"])
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    assert render(lv) =~ ~s(data-mention-tags="#{tags}")
    assert has_element?(lv, ~s(#message-#{mention.id} .message-body a[href="/u/#{reader.id}"]))

    # Nothing unread, nothing glows.
    {:ok, lv, _html} =
      conn
      |> log_in_user(reader)
      |> live_isolated(IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    refute has_element?(lv, "[data-mention-glow]")
    refute render(lv) =~ "data-mention-tags"

    js = File.read!("assets/js/mention_glow.js")
    assert js =~ "li.dataset.glowing = li.dataset.mentionGlow"
    assert js =~ ~s|link.classList.add("mention-pulse")|

    css = File.read!("assets/css/app.css")
    assert css =~ ~s|[data-glowing="mention"] { --mention-glow: var(--color-error); }|
    assert css =~ "animation: mention-glow 4.3s ease-out both"
    assert css =~ "7%, 30.2% {"
    assert css =~ "animation: mention-pulse 0.5s ease-in-out 3"
  end
end
