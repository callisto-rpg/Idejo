# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.InlineLinksTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Markdown
  alias Idejo.Messages.Body
  alias Idejo.Notifications.Notification
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff room"})

    for role <- [:guest, :member],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), staff, :view, :deny)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, staff: staff}
  end

  defp topic!(user, category, title) do
    {:ok, topic} = Forum.create_topic(user, category, %{"title" => title, "body" => "Hi"})
    topic
  end

  defp role!(admin, base, attrs \\ %{}) do
    {:ok, role} = Access.create_role(admin, Map.put(attrs, "name", unique_role_name(base)))
    role
  end

  defp holder!(role) do
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  defp notified?(user, message),
    do:
      Repo.exists?(
        from n in Notification, where: n.user_id == ^user.id and n.message_id == ^message.id
      )

  @tag req: "TP-10"
  test "TP-10 +role, #topic, /category and $tag are found outside code and links, not in words" do
    md = """
    Ask +moderator or +help-desk about #garden-plans in /help, tagged $bug.
    Not these: C#, and/or, /usr/bin, a/b, +1, $5, x#y, `#code`, [#l](/x), https://x.org/help

    # A heading
    """

    assert Markdown.references(md) == [
             role: "moderator",
             role: "help-desk",
             topic: "garden-plans",
             category: "help",
             tag: "bug"
           ]
  end

  @tag req: "TP-10"
  test "TP-10 links read the name, unless it lives where some readers may not look", %{
    admin: admin,
    general: general,
    staff: staff
  } do
    author = user_with_role_fixture(:moderator)
    public = topic!(author, general, "Garden plans")
    secret = topic!(author, staff, "Pay rises")
    {:ok, tag} = Tags.create_tag(admin, %{"name" => unique_role_name("Bug")})

    {:ok, staff_tag} =
      Tags.create_tag(admin, %{"name" => unique_role_name("Rota"), "category_id" => staff.id})

    md =
      "See ##{public.slug}, ##{secret.slug}, /#{general.slug}, /#{staff.slug}, $#{tag.slug}, $#{staff_tag.slug}, #nothing-here"

    html = Body.to_html(md, author: author, category_id: general.id)
    assert html =~ ~s(<a href="/t/#{public.id}" rel="noopener noreferrer">#Garden plans</a>)
    assert html =~ ~s(<a href="/t/#{secret.id}" rel="noopener noreferrer">##{secret.slug}</a>)
    assert html =~ ~s(<a href="/c/#{general.slug}" rel="noopener noreferrer">/General</a>)
    assert html =~ ~s(<a href="/c/#{staff.slug}" rel="noopener noreferrer">/#{staff.slug}</a>)
    assert html =~ ~s(>$#{tag.name}</a>)
    assert html =~ ~s(>$#{staff_tag.slug}</a>)
    refute html =~ "Pay rises"
    assert html =~ "#nothing-here"
    refute html =~ ~s(>#nothing-here</a>)

    # Written in the staff room, staff room names show.
    assert Body.to_html("##{secret.slug}", author: author, category_id: staff.id) =~ "#Pay rises"

    # An author who may not view a place does not link it.
    member = user_fixture()

    refute Body.to_html("##{secret.slug} /#{staff.slug}", author: member, category_id: general.id) =~
             "<a"
  end

  @tag req: "TP-10"
  test "TP-10 a #slug shared by topics leads to the one its author last wrote in", %{
    general: general
  } do
    author = user_fixture()
    mine = topic!(author, general, "Plans")
    newer = topic!(user_fixture(), general, "Plans")
    assert mine.slug == newer.slug

    assert Body.to_html("#plans", author: author, category_id: general.id) =~ "/t/#{mine.id}"

    assert Body.to_html("#plans", author: user_fixture(), category_id: general.id) =~
             "/t/#{newer.id}"
  end

  @tag req: "TP-10"
  test "TP-10 +role: tagged by everyone, or by roles above that tag roles beneath; never member",
       %{
         admin: admin
       } do
    open = role!(admin, "Help desk", %{"mentionable" => "true"})
    quiet = role!(admin, "Quiet")
    member = user_fixture()
    moderator = user_with_role_fixture(:moderator)

    slugs = &(&1 |> Access.mentionable_roles() |> Enum.map(fn role -> Access.role_slug(role) end))

    # Out of the box: owner, administrator and moderator are tagged by everyone.
    assert ~w(owner administrator moderator) -- slugs.(member) == []
    assert Access.role_slug(open) in slugs.(member)
    refute Access.role_slug(quiet) in slugs.(member)

    # Moderators tag the roles beneath them; nobody tags member or guest.
    assert Access.role_slug(quiet) in slugs.(moderator)
    refute "member" in slugs.(moderator)
    refute "guest" in slugs.(admin)
    assert Access.role_slug(quiet) in slugs.(admin)

    # A role that tags roles beneath, ranked above another custom role.
    lead = role!(admin, "Lead", %{"mentions_below" => "true"})
    {:ok, _} = Access.move_role(admin, lead, :up)
    assert Access.role_slug(quiet) in slugs.(holder!(lead))

    assert slugs.(nil) == []
  end

  @tag req: "TP-10"
  test "TP-10 +role notifies the role's members who may view the topic, when allowed", %{
    admin: admin,
    general: general,
    staff: staff
  } do
    quiet = role!(admin, "Quiet")
    reader = holder!(quiet)
    blind = holder!(quiet)
    {:ok, _} = Access.set_permission(admin, quiet, general, :view, :allow)

    {:ok, team} =
      Access.create_role(admin, %{"name" => unique_role_name("Team"), "mentionable" => "true"})

    team_member = holder!(team)

    topic = topic!(admin, general, "Hello")
    slug = Access.role_slug(quiet)

    # A member may not tag "quiet": it stays text and nobody is notified.
    {:ok, plain} = Forum.post_message(user_fixture(), topic, %{"body" => "Hey +#{slug}"})
    refute plain.body_html =~ "<a"
    refute notified?(reader, plain)

    # A moderator may: its members are notified as a mention.
    moderator = user_with_role_fixture(:moderator)
    {:ok, ping} = Forum.post_message(moderator, topic, %{"body" => "Hey +#{slug}"})
    assert ping.body_html =~ ~s(href="/r/#{slug}")
    assert ping.body_html =~ ">+#{quiet.name}</a>"

    assert Repo.get_by!(Notification, user_id: reader.id, message_id: ping.id).kind ==
             "role_mention"

    assert notified?(blind, ping)

    # Only those who may view the topic.
    hidden = topic!(admin, staff, "Staff only")
    {:ok, ping} = Forum.post_message(admin, hidden, %{"body" => "+#{Access.role_slug(team)}"})
    refute notified?(team_member, ping)

    # Built-in names read capitalised.
    assert Body.to_html("+moderator", author: user_fixture()) =~ ">+Moderator</a>"
  end

  @tag req: "TP-10"
  test "TP-10 an @mention makes the user follow the topic, unless they unfollowed it", %{
    general: general
  } do
    ada = user_fixture()
    bea = user_fixture()
    topic = topic!(user_fixture(), general, "Picnic")
    :ok = Reading.unfollow(bea, topic)

    {:ok, _} =
      Forum.post_message(user_fixture(), topic, %{"body" => "@#{ada.username} @#{bea.username}"})

    assert Reading.following?(ada, topic)
    refute Reading.following?(bea, topic)
  end

  @tag req: "TP-10"
  test "TP-10 administrators set who may tag a role, audited", %{admin: admin} do
    role = role!(admin, "Crew")
    refute role.mentionable

    {:ok, role} =
      Access.update_role(admin, role, %{"mentionable" => "true", "mentions_below" => "true"})

    assert role.mentionable and role.mentions_below
    entry = Enum.find(Audit.list_entries(), &(&1.change == "role.update"))
    assert entry.before["mentionable"] == false
    assert entry.after["mentionable"] == true

    # Member and guest take no mention settings.
    {:ok, member} =
      Access.update_role(admin, Access.built_in_role!(:member), %{"mentionable" => "true"})

    refute member.mentionable
  end
end
