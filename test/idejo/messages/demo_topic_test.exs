# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.DemoTopicTest do
  use ExUnit.Case, async: true

  alias Idejo.Messages.DemoTopic

  @ana %{id: "ana", name: "Ana", role: "Member"}

  defp start(window) do
    start_supervised!({DemoTopic, name: nil, window_seconds: window, broadcast: false})
  end

  @tag req: "GM-02"
  test "GM-02 Enter replaces the open message's text instead of opening another" do
    topic = start(45)
    {:ok, first} = DemoTopic.commit(topic, @ana, "Hello.")
    {:ok, second} = DemoTopic.commit(topic, @ana, "Hello. How are you?")

    assert first.id == second.id
    assert [%{body: "Hello. How are you?", state: :open}] = DemoTopic.list(topic)
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter keeps the message open within the window" do
    topic = start(45)
    {:ok, message} = DemoTopic.commit(topic, @ana, "Hi.", break: true)
    assert message.state == :open
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter after the window closes the message" do
    topic = start(0)
    {:ok, message} = DemoTopic.commit(topic, @ana, "Hi.", break: true)
    assert message.state == :closed
  end

  @tag req: "GM-04"
  test "GM-04 Enter after the window still commits to the same message" do
    topic = start(0)
    {:ok, first} = DemoTopic.commit(topic, @ana, "Hi.")
    {:ok, second} = DemoTopic.commit(topic, @ana, "Hi. Still here.")
    assert first.id == second.id and second.state == :open
  end
end
