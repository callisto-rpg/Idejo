# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.MakeMemberImplicit do
  use Ecto.Migration

  # RP-01: member is implicit for every verified user, like guest for visitors, so it is no
  # longer stored. Remove the rows written by verification and by the roles migration.
  def up do
    execute """
    DELETE FROM user_roles
    USING roles
    WHERE user_roles.role_id = roles.id AND roles.built_in AND roles.name IN ('member', 'guest')
    """
  end

  # Going back restores stored membership for verified users.
  def down do
    execute """
    INSERT INTO user_roles (user_id, role_id)
    SELECT users.id, roles.id FROM users, roles
    WHERE users.confirmed_at IS NOT NULL AND roles.built_in AND roles.name = 'member'
    ON CONFLICT DO NOTHING
    """
  end
end
