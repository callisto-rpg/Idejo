# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumLinksTest do
  @moduledoc """
  `&forum` links (steward request, 2026-11-13): a message names another forum of its
  author's by the first label of its address; it becomes a link only when the author joined
  it (the community menu's answer) and the public directory lists it. Not async: the
  community settings are the application's.
  """
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts.UserIdentity
  alias Idejo.{Markdown, Suggestions}
  alias Idejo.Messages.Body

  @issuer "https://id.example.test"

  setup do
    community = Application.get_env(:idejo, :community)
    oidc = Application.get_env(:idejo, :oidc)

    on_exit(fn ->
      Application.put_env(:idejo, :community, community)

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)
    end)

    Application.put_env(:idejo, :community,
      url: "http://hub.example.test/internal/community",
      directory_url: "https://forums.example.test/"
    )

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "client",
      client_secret: "secret",
      label: "Example ID"
    )

    # Hosts of their own in each test: the answers are kept a few minutes per host.
    n = System.unique_integer([:positive])
    garden = "garden#{n}.idejo.test"
    kitchen = "kitchen#{n}.idejo.test"

    Req.Test.stub(Idejo.Community, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case {conn.host, conn.request_path} do
        {"hub.example.test", "/internal/community"} ->
          Req.Test.json(conn, %{
            "communities" => [
              %{"name" => "Garden club", "url" => "https://#{garden}/"},
              %{"name" => "Kitchen", "url" => "https://#{kitchen}/"}
            ]
          })

        # The directory lists the garden only.
        {"forums.example.test", "/api/forums"} ->
          listed = if conn.query_params["q"] == garden, do: [garden], else: []

          Req.Test.json(conn, %{
            "forums" => Enum.map(listed, &%{"name" => "Garden club", "url" => "https://#{&1}/"})
          })
      end
    end)

    ada = user_fixture()
    Repo.insert!(UserIdentity.changeset(%{user_id: ada.id, issuer: @issuer, subject: "s#{n}"}))

    %{ada: ada, n: n, garden: garden, kitchen: kitchen}
  end

  test "&forum is read outside code, never inside a word or as an HTML entity", %{n: n} do
    assert Markdown.references("See &garden#{n} and R&D, &amp; `&code`, &semi; &a-b") ==
             [{:forum, "garden#{n}"}, {:forum, "a-b"}]
  end

  test "a forum the author joined and the directory lists becomes a link to it", %{
    ada: ada,
    n: n,
    garden: garden
  } do
    html = Body.to_html("Come to &garden#{n}, &kitchen#{n} or &nowhere.", author: ada)

    [link] = html |> LazyHTML.from_fragment() |> LazyHTML.query("a") |> Enum.to_list()
    assert LazyHTML.attribute(link, "href") == ["https://#{garden}/"]
    assert LazyHTML.attribute(link, "title") == ["&#{garden}"]
    assert LazyHTML.text(link) == "&Garden club"

    # The API reads it as an inline link, by its host (AP-11).
    assert Idejo.Api.Structure.mentions(html) == [
             %{type: "forum", ref: garden, text: "&Garden club"}
           ]

    # Not listed in the directory, or not joined: plain text.
    assert html =~ "&amp;kitchen#{n}"
    assert html =~ "&amp;nowhere"
    refute html =~ "kitchen#{n}.idejo.test"

    # Someone not linked to the provider has no communities.
    assert Body.to_html("&garden#{n}", author: user_fixture()) =~ "<p>&amp;garden#{n}</p>"
  end

  test "& suggests the author's listed forums", %{ada: ada, n: n, garden: garden} do
    assert Suggestions.kind("&") == :forum

    assert [%{slug: slug, name: "Garden club", host: ^garden}] =
             Suggestions.suggest(ada, :forum, "")

    assert slug == "garden#{n}"
    assert [_] = Suggestions.suggest(ada, :forum, "gar")
    assert Suggestions.suggest(ada, :forum, "kit") == []
  end
end
