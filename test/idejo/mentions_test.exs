# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MentionsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Markdown
  alias Idejo.Messages
  alias Idejo.Messages.Body

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{ada: user_fixture(%{username: "ada_love", display_name: "Ada"})}
  end

  @tag req: "TP-10"
  test "TP-10 @usernames are found in the text, never in code or links" do
    md = """
    Hi @Ada_Love and @bob, mail a@b.com or see [@carl](https://example.org).
    `@code` and *@emphasised*; @ab is too short; again @ada_love.

    ```
    @fenced
    ```
    """

    assert Enum.sort(Markdown.mentions(md)) == ["ada_love", "bob", "emphasised"]
    assert Markdown.mentions("no at sign") == []
  end

  @tag req: "TP-10"
  test "TP-10 a mention of an existing user links to their URI path; others stay text", %{
    ada: ada
  } do
    html = Body.to_html("Hi @Ada_Love, and @nobody_here. Mail a@b.com, `@ada_love`")

    assert html =~ ~s(<a href="/u/#{ada.id}" rel="noopener noreferrer">@Ada_Love</a>)
    assert html =~ "@nobody_here."
    refute html =~ ~s(>@nobody_here</a>)
    assert html =~ "<code>@ada_love</code>"
    assert html =~ ~s(href="mailto:a@b.com")
    assert [%{id: id}] = Body.mentioned_users("@ada_love @ADA_LOVE @nobody_here")
    assert id == ada.id
  end

  @tag req: "TP-10"
  test "TP-10 a deleted account is not mentioned", %{ada: ada} do
    {:ok, _} = Accounts.delete_user(ada, valid_user_password())
    assert Body.mentioned_users("@ada_love") == []
    refute Body.to_html("@ada_love") =~ "<a"
  end

  @tag req: "TP-10"
  test "TP-10 every way of posting stores mentions as links", %{ada: ada} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    link = ~s(href="/u/#{ada.id}")

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "T", "body" => "Hey @ada_love"})

    assert [%{body_html: first}] = Forum.list_messages(topic)
    assert first =~ link

    {:ok, posted} = Forum.post_message(user_fixture(), topic, %{"body" => "And @ada_love"})
    assert posted.body_html =~ link

    author = user_fixture()
    {:ok, open} = Messages.commit(author, topic, "Hello")
    {:ok, grown} = Messages.commit(author, topic, "Hello. Ping @ada_love")
    refute open.body_html =~ link
    assert grown.body_html =~ link

    {:ok, closed} = Forum.post_message(author, topic, %{"body" => "Plain"})
    {:ok, edited} = Messages.edit(author, closed, "Now @ada_love")
    assert edited.body_html =~ link
  end
end
