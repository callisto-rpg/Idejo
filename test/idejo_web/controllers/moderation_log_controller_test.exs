# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ModerationLogControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(user_fixture(), general, %{"title" => "T", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{topic: topic}
  end

  @tag req: "MO-03"
  test "MO-03 moderators read the log; others do not find it", %{topic: topic} do
    moderator = user_with_role_fixture(:moderator, %{display_name: "Mo"})
    {:ok, message} = Messages.commit(user_fixture(), topic, "Open")
    {:ok, _} = Messages.close_as_moderator(moderator, message, "Spam <b>bot</b>")

    conn = log_in_user(build_conn(), moderator)
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(id="moderation-link")

    page = conn |> get(~p"/moderation/log") |> html_response(200)
    assert page =~ "Mo"
    assert page =~ "Closed an open message"
    assert page =~ ~s(href="/m/#{message.id}")
    assert page =~ "Spam &lt;b&gt;bot&lt;/b&gt;"

    member = log_in_user(build_conn(), user_fixture())
    refute member |> get(~p"/") |> html_response(200) =~ "moderation-link"
    assert_error_sent 404, fn -> get(member, ~p"/moderation/log") end
    assert redirected_to(get(build_conn(), ~p"/moderation/log")) == ~p"/users/sign-in"
  end
end
