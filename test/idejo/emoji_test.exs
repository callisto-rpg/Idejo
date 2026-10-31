# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.EmojiTest do
  use ExUnit.Case, async: true

  alias Idejo.Emoji
  alias Idejo.Markdown
  alias Vix.Vips.Image

  @tag req: "TP-17"
  test "TP-17 :name: and typed emoji are drawn with Twemoji or the server's own images" do
    html =
      Markdown.to_html(
        "Hi :joy: :+1: :agree: :nothing: at 12:30:45, ❤ 👨‍👩‍👧 🇫🇷 `:joy: 😂` [:tada:](/x)"
      )

    assert html =~ ~s(<img src="/emoji/1f602.svg?vsn=#{Emoji.version()}" alt="😂" title=":joy:">)
    assert html =~ ~s(<img src="/emoji/1f44d.svg?vsn=#{Emoji.version()}" alt="👍" title=":+1:">)

    assert html =~
             ~s(<img src="/reactions/agree.png?vsn=#{Emoji.version()}" alt=":agree:" title=":agree:">)

    assert html =~ ":nothing:"
    assert html =~ "12:30:45"
    # A heart typed without U+FE0F, a family as one image, a flag.
    assert html =~ ~s(src="/emoji/2764.svg?vsn=#{Emoji.version()}")
    assert html =~ ~s(src="/emoji/1f468-200d-1f469-200d-1f467.svg?vsn=#{Emoji.version()}")
    assert html =~ ~s(src="/emoji/1f1eb-1f1f7.svg?vsn=#{Emoji.version()}")
    # Code stays as written; links keep their emoji.
    assert html =~ "<code>:joy: 😂</code>"

    assert html =~
             ~s(<a href="/x" rel="noopener noreferrer"><img src="/emoji/1f389.svg?vsn=#{Emoji.version()}")

    assert Markdown.to_html("plain text") == "<p>plain text</p>"
  end

  @tag req: "TP-17"
  test "TP-17 an excerpt keeps emoji as characters" do
    message = %Idejo.Messages.Message{body_html: Markdown.to_html("So :joy: and :agree:")}
    assert Idejo.Forum.excerpt(message) == "So 😂 and :agree:"
  end

  @tag req: "TP-17"
  test "TP-17 every emoji has its image, served by the app (SP-04)" do
    for {_category, entries} <- Emoji.groups(), emoji <- entries do
      path = Path.join("priv/static", URI.parse(emoji.src).path)
      assert File.exists?(path), "#{emoji.name}: #{path} is missing"
    end

    assert Enum.map(Emoji.defaults(), & &1.name) ==
             ~w(agree disagree this same yes no joy heart)

    assert [{"Server", [%{name: "bruh"}]}] = Emoji.groups("bruh")
    assert "joy" in (Emoji.groups(":joy:") |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(& &1.name))
  end

  # Steward decision, 2026-10-31: the + picker draws every emoji from one sprite sheet.
  @tag req: "TP-17"
  test "TP-17 the picker's sprite sheet holds every picker emoji, made from the current images" do
    assert %{src: "/emoji/sprite.webp?vsn=" <> _, columns: columns, rows: rows} = Emoji.sprite(),
           "priv/emoji/sprite.json is stale: run mix run --no-start priv/emoji/sprite.exs"

    data = "priv/emoji/sprite.json" |> File.read!() |> Jason.decode!()
    names = Enum.map(Emoji.picker_images(), &elem(&1, 0))
    assert data["names"] == names
    assert data["version"] == Emoji.version()
    assert rows == div(length(names) + columns - 1, columns)

    {:ok, sheet} = Image.new_from_file("priv/static/emoji/sprite.webp")
    assert Image.width(sheet) == columns * 36
    assert Image.height(sheet) == rows * 36
  end
end
