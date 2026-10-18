# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.UserRole do
  @moduledoc """
  A role held by a user. Guest is never stored: it is the role of visitors and of users
  who have not verified their email address.
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "user_roles" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    belongs_to :role, Idejo.Access.Role, primary_key: true
  end
end
