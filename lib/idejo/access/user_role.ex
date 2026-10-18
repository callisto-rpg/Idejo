# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.UserRole do
  @moduledoc """
  A role held by a user. Guest and member are never stored: guest is the role of visitors
  and unverified users, member that of every verified user (see `Idejo.Access.roles_of/1`).
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "user_roles" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    belongs_to :role, Idejo.Access.Role, primary_key: true
  end
end
