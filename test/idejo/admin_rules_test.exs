# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): every admin panel action refuses anyone
# but an owner or administrator in its context (AD-02), whoever calls it, not only behind
# `/admin`'s plug. Not async: plugins use a shared folder.
defmodule Idejo.AdminRulesTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.OIDCRegistry
  alias Idejo.Forum
  alias Idejo.Forum.{Tags, TopicIcons}
  alias Idejo.Messages.Automessages
  alias Idejo.Plugins
  alias Idejo.Settings
  alias Idejo.Settings.{InfoBoxes, Logo}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, category} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, group} = Forum.create_group(admin, %{"name" => "Main"})
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Helpers")})
    {:ok, tag} = Tags.create_tag(admin, %{"name" => "Help #{System.unique_integer([:positive])}"})
    {:ok, icon} = TopicIcons.create(admin, image_file(:png), %{"name" => "Star"})
    {:ok, box} = InfoBoxes.create(admin, %{"title" => "Events", "body_md" => "Soon"})

    {:ok, automessage} =
      Automessages.create(admin, %{
        "command" => "hello#{System.unique_integer([:positive])}",
        "body_md" => "Hello",
        "sender_username" => "idejo"
      })

    moderator = user_with_role_fixture(:moderator)

    %{
      admin: admin,
      callers: [user_fixture(), moderator],
      category: category,
      group: group,
      role: role,
      tag: tag,
      icon: icon,
      box: box,
      automessage: automessage
    }
  end

  defp admin_actions(ctx, user) do
    %{category: category, group: group, role: role, tag: tag, icon: icon, box: box} = ctx
    target = user_fixture()

    [
      settings: fn -> Settings.update_settings(user, %{"server_name" => "Taken"}) end,
      logo: fn -> Logo.set(user, image_file(:png)) end,
      logo_remove: fn -> Logo.remove(user) end,
      create_role: fn -> Access.create_role(user, %{"name" => unique_role_name("X")}) end,
      update_role: fn -> Access.update_role(user, role, %{"name" => "Renamed"}) end,
      move_role: fn -> Access.move_role(user, role, :up) end,
      delete_role: fn -> Access.delete_role(user, role) end,
      set_permission: fn -> Access.set_permission(user, role, category, :view, :allow) end,
      assign_role: fn -> Access.assign_role(user, target, role) end,
      unassign_role: fn -> Access.unassign_role(user, target, role) end,
      create_category: fn -> Forum.create_category(user, %{"name" => "Mine"}) end,
      update_category: fn -> Forum.update_category(user, category, %{"name" => "Mine"}) end,
      move_category: fn -> Forum.move_category(user, category, :up) end,
      delete_category: fn -> Forum.delete_category(user, category) end,
      create_group: fn -> Forum.create_group(user, %{"name" => "Mine"}) end,
      update_group: fn -> Forum.update_group(user, group, %{"name" => "Mine"}) end,
      move_group: fn -> Forum.move_group(user, group, :up) end,
      delete_group: fn -> Forum.delete_group(user, group) end,
      create_tag: fn -> Tags.create_tag(user, %{"name" => "Mine"}) end,
      update_tag: fn -> Tags.update_tag(user, tag, %{"name" => "Mine"}) end,
      delete_tag: fn -> Tags.delete_tag(user, tag) end,
      create_icon: fn -> TopicIcons.create(user, image_file(:png), %{"name" => "Mine"}) end,
      delete_icon: fn -> TopicIcons.delete(user, icon) end,
      create_box: fn -> InfoBoxes.create(user, %{"title" => "Mine", "body_md" => "x"}) end,
      update_box: fn -> InfoBoxes.update(user, box, %{"title" => "Mine"}) end,
      move_box: fn -> InfoBoxes.move(user, box, :up) end,
      delete_box: fn -> InfoBoxes.delete(user, box) end,
      create_automessage: fn ->
        Automessages.create(user, %{"command" => "mine", "body_md" => "x"})
      end,
      update_automessage: fn ->
        Automessages.update(user, ctx.automessage, %{"body_md" => "x"})
      end,
      delete_automessage: fn -> Automessages.delete(user, ctx.automessage) end,
      plugin_enable: fn -> Plugins.set_enabled(user, "youtube", true) end,
      plugin_roles: fn -> Plugins.set_roles(user, "youtube", []) end,
      plugin_install: fn -> Plugins.install(user, "{}") end,
      invite: fn -> Accounts.create_invite(user) end,
      registry_connect: fn -> OIDCRegistry.connect(user) end,
      registry_disconnect: fn -> OIDCRegistry.disconnect(user) end,
      registry_listed: fn -> OIDCRegistry.set_listed(user, true) end
    ]
  end

  @tag req: "AD-02"
  test "AD-02 every admin action refuses a member and a moderator in its context", ctx do
    for caller <- ctx.callers, {name, action} <- admin_actions(ctx, caller) do
      assert action.() == {:error, :forbidden}, "#{name} was not refused"
    end

    # Nothing changed.
    assert Settings.get(:server_name) != "Taken"
    assert Repo.reload(ctx.category).name == "General"
    assert Repo.reload(ctx.role)
    assert Repo.reload(ctx.tag)
    assert Repo.reload(ctx.icon)
    assert Repo.reload(ctx.box).title == "Events"
  end

  @tag req: "AD-02"
  test "AD-02 the setup's own settings, with no one acting, still go through" do
    assert {:ok, _} = Settings.update_settings(nil, %{"server_name" => "Fresh"})
    assert Settings.get(:server_name) == "Fresh"
  end

  @tag req: "RP-03"
  test "RP-03 a moderator archiving the first topic still hides the Archive", %{
    admin: admin,
    category: category,
    tag: tag
  } do
    moderator = user_with_role_fixture(:moderator)

    {:ok, topic} =
      Forum.create_topic(admin, category, %{
        "title" => "Old",
        "body" => "Done",
        "tag_ids" => [tag.id]
      })

    assert {:ok, archived} = Forum.archive_topic(moderator, topic, "Done")
    assert archived.state == "archived"
    refute Access.can?(user_fixture(), :view, Repo.get!(Forum.Category, archived.category_id))
  end
end
