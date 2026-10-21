# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Seeds a server for the load test (docs/load-testing.md): an owner, 200 verified people
# (load0001@example.org …, password "load test passphrase") and a "Load test" category with
# 10 topics. Run inside the app, on an empty database:
#
#   bin/idejo rpc 'Code.eval_file("/load/seed.exs")'

alias Idejo.{Access, Accounts, Forum, Repo}

users = 200
topics = 10
password = "load test passphrase"

person = fn username, name ->
  {:ok, user} =
    Accounts.register_user(
      %{
        email: "#{username}@example.org",
        username: username,
        display_name: name,
        password: password
      },
      skip_invite: true
    )

  Repo.update!(Ecto.Changeset.change(user, confirmed_at: DateTime.utc_now(:second)))
end

admin = person.("loadadmin", "Load admin")
:ok = Access.grant_role(admin, Access.built_in_role!(:owner))

people =
  for i <- 1..users do
    n = String.pad_leading(Integer.to_string(i), 4, "0")
    person.("load#{n}", "Person #{n}")
  end

{:ok, category} = Forum.create_category(admin, %{"name" => "Load test"})

for t <- 1..topics do
  {:ok, _} =
    Forum.create_topic(Enum.at(people, rem(t, users)), category, %{
      "title" => "Load topic #{t}",
      "body" => "The start of topic #{t}."
    })
end

IO.puts("Seeded #{users} people and #{topics} topics.")
