# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AC06IgnoreTest do
  @moduledoc """
  AC-06: a member ignores someone from their card; that person's messages are collapsed for
  them, and only for them. Profile and account lists whom they ignore.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    reader = user_fixture()
    rude = user_fixture(%{display_name: "Rude Ruth"})
    {:ok, topic} = Forum.create_topic(admin, general, %{"title" => "Chat", "body" => "Hi"})
    {:ok, message} = Forum.post_message(rude, topic, %{"body" => "Something rude"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{reader: reader, rude: rude, topic: topic, message: message}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "AC-06"
  test "AC-06 ignoring: not oneself, nor a server account; twice is fine; undone", %{
    reader: reader,
    rude: rude
  } do
    assert Accounts.ignore_user(reader, reader) == {:error, :forbidden}
    assert Accounts.ignore_user(reader, %{rude | status: "system"}) == {:error, :forbidden}

    refute Accounts.ignoring?(reader, rude)
    assert Accounts.ignore_user(reader, rude) == :ok
    assert Accounts.ignore_user(reader, rude) == :ok
    assert Accounts.ignoring?(reader, rude)
    refute Accounts.ignoring?(rude, reader)
    assert Accounts.ignored_ids(reader) == MapSet.new([rude.id])
    assert Enum.map(Accounts.list_ignored(reader), & &1.id) == [rude.id]

    assert Accounts.unignore_user(reader, rude) == :ok
    refute Accounts.ignoring?(reader, rude)
  end

  @tag req: "AC-06"
  test "AC-06 Ignore on the card collapses their messages, for the reader only", %{
    conn: conn,
    reader: reader,
    rude: rude,
    topic: topic,
    message: message
  } do
    conn = log_in_user(conn, reader)

    html = conn |> get(~p"/u/#{rude.id}") |> html_response(200)
    assert html =~ ~s(id="ignore-user")

    conn =
      post(conn, ~p"/u/#{rude.id}/ignore", %{"return_to" => "/t/#{topic.id}/#{topic.slug}"})

    assert redirected_to(conn) == "/t/#{topic.id}/#{topic.slug}"
    assert Accounts.ignoring?(reader, rude)

    {:ok, lv, _html} = watch(log_in_user(build_conn(), reader), topic)
    assert has_element?(lv, "details#message-#{message.id}-ignored summary", "Rude Ruth")
    # Collapsed, not removed: it opens on demand.
    assert has_element?(lv, "#message-#{message.id}-ignored", "Something rude")

    # Nobody else sees it collapsed, nor does the author.
    {:ok, other, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)
    refute has_element?(other, "#message-#{message.id}-ignored")
    {:ok, own, _html} = watch(log_in_user(build_conn(), rude), topic)
    refute has_element?(own, "#message-#{message.id}-ignored")
    # The card never shows anyone their own Ignore button.
    refute build_conn() |> log_in_user(rude) |> get(~p"/u/#{rude.id}") |> html_response(200) =~
             ~s(id="ignore-user")
  end

  @tag req: "AC-06"
  test "AC-06 Profile and account lists whom one ignores, with Stop ignoring", %{
    conn: conn,
    reader: reader,
    rude: rude,
    topic: topic,
    message: message
  } do
    conn = log_in_user(conn, reader)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "#ignored-none")

    :ok = Accounts.ignore_user(reader, rude)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "#ignored-#{rude.id}", "Rude Ruth")

    conn = delete(conn, ~p"/u/#{rude.id}/ignore", %{"return_to" => "/users/settings"})
    assert redirected_to(conn) == ~p"/users/settings"
    refute Accounts.ignoring?(reader, rude)

    {:ok, lv, _html} = watch(log_in_user(build_conn(), reader), topic)
    refute has_element?(lv, "#message-#{message.id}-ignored")
    assert has_element?(lv, "#message-#{message.id}", "Something rude")
  end

  @tag req: "AC-06"
  test "AC-06 visitors cannot ignore anyone", %{conn: conn, rude: rude} do
    refute conn |> get(~p"/u/#{rude.id}") |> html_response(200) =~ ~s(id="ignore-user")
    conn = post(conn, ~p"/u/#{rude.id}/ignore")
    assert redirected_to(conn) =~ "/users/sign-in"
  end
end
