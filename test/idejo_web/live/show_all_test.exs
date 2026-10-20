# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ShowAllTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  # Far longer than any screen: 2,000 paragraphs, about 140 kB of Markdown.
  @long Enum.map_join(1..2000, "\n\n", &"Paragraph #{&1} of a very long message.")

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{topic: topic, general: general}
  end

  @tag req: "GM-06"
  test "GM-06 messages have no size limit", %{topic: topic, general: general} do
    author = user_fixture()

    {:ok, open} = Messages.commit(author, topic, @long)
    assert open.body_md == @long
    assert open.body_html =~ "Paragraph 2000 of a very long message."

    {:ok, longer} = Messages.commit(author, topic, @long <> "\n\nAnd one more")
    assert longer.id == open.id
    assert longer.body_md =~ "And one more."

    {:ok, closed} = Messages.close(longer)
    {:ok, edited} = Messages.edit(author, closed, "Short now.\n\n" <> @long)
    assert edited.body_md == "Short now.\n\n" <> @long

    {:ok, posted} = Forum.post_message(user_fixture(), topic, %{"body" => @long})
    assert posted.body_md == @long

    {:ok, started} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Long", "body" => @long})

    assert [%{body_md: @long}] = Forum.list_messages(started)
  end

  @tag req: "GM-06"
  test "GM-06 every message body comes in full with a Show all control for long ones", %{
    conn: conn,
    topic: topic
  } do
    {:ok, posted} = Forum.post_message(user_fixture(), topic, %{"body" => @long})

    {:ok, lv, html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    # The whole text is in the page, also without JavaScript; the hook collapses it on
    # screens it does not fit and shows the button, which controls the text.
    for page <- [html, render(lv)] do
      assert page =~ "Paragraph 2000 of a very long message."
    end

    body = "#message-#{posted.id}-body"
    assert has_element?(lv, "#{body}[phx-hook=ShowAll]")
    assert has_element?(lv, "#{body}-text.message-body")

    assert has_element?(
             lv,
             ~s(#{body} button.show-all[aria-controls="message-#{posted.id}-body-text"]),
             "Show all"
           )
  end
end
