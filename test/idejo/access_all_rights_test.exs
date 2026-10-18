# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccessAllRightsTest do
  @moduledoc """
  Owners and administrators always have every right and can never lock themselves out.
  """
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access

  defp holding(user, role) do
    :ok = Access.grant_role(user, Access.built_in_role!(role))
    user
  end

  @tag req: "AD-02"
  test "AD-02 owners and administrators are administrators, whatever else they hold" do
    for role <- [:owner, :administrator] do
      assert Access.administrator?(user_fixture() |> holding(role))
      assert Access.administrator?(user_fixture() |> holding(role) |> holding(:moderator))
    end
  end

  @tag req: "AD-02"
  test "AD-02 owners and administrators keep their rights before verifying their email" do
    for role <- [:owner, :administrator] do
      assert Access.administrator?(unconfirmed_user_fixture() |> holding(role))
    end
  end

  @tag req: "AD-02"
  test "AD-02 other roles, visitors and unverified users are not administrators" do
    refute Access.administrator?(nil)
    refute Access.administrator?(user_fixture())
    refute Access.administrator?(user_fixture() |> holding(:moderator))
    refute Access.administrator?(unconfirmed_user_fixture() |> holding(:moderator))
  end
end
