# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# NF-03 (docs/page-speed.md): an owner, a public category and a 300-message topic with
# messages of several kinds (lists, links, emoji, a photo every 50th) and some reactions,
# for measuring the public topic page. Run once, on an empty database:
# `mix run load/page_speed_seed.exs`. Prints the topic's address.
Application.put_env(:idejo, :rate_limits, enabled: false)
alias Idejo.{Accounts, Access, Forum, Repo, Reactions, Uploads}

user = fn name, role ->
  {:ok, u} =
    Accounts.register_user(
      %{
        email: "#{name}@example.org",
        username: name,
        display_name: String.capitalize(name),
        password: "a long password here"
      },
      skip_invite: true,
      welcomed: true
    )

  u = u |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second)) |> Repo.update!()
  if role, do: :ok = Access.grant_role(u, Access.built_in_role!(role))
  u
end

owner = user.("owner", :owner)
people = for n <- ~w(ada bob cleo devi eli fay gus), do: user.(n, nil)
{:ok, general} = Forum.create_category(owner, %{"name" => "General"})

lines = [
  "Has anyone tried the new trail along the river? I went on Sunday and it was **much** quieter than I expected.",
  "Yes! The part after the bridge is the best. Bring water though, there is no fountain until the village.",
  "I keep a list of the spots I liked:\n\n- the old mill\n- the bench under the oak\n- the café at the end, which opens at 9",
  "Small tip: the map on [the town's site](https://example.org/map) is out of date, the path moved last spring.",
  "Does it work by bike? My knees do not like long walks any more :sweat_smile:",
  "By bike it's fine until the forest, then it gets rocky. A gravel bike is enough.",
  "We should organise a group walk one Saturday. Who would be in?",
  "I'm in, any Saturday but the 14th.",
  "Count me in too. Should we meet at the station at 10?",
  "10 works. I'll bring a thermos of tea for everyone :tea:"
]

{:ok, topic} =
  Forum.create_topic(owner, general, %{
    "title" => "Walks along the river",
    "body" =>
      "A topic for everything about the river trail: tips, photos, meet-ups.\n\nPlease keep it friendly :slightly_smiling_face:"
  })

{:ok, image} = Image.new(1200, 800, color: :steelblue)
path = Path.join(System.tmp_dir!(), "nf03-photo.jpg")
Image.write!(image, path)
{:ok, upload} = Uploads.store_image(Enum.at(people, 2), path)

messages =
  for i <- 1..300 do
    author = Enum.at(people, rem(i, length(people)))
    body = Enum.at(lines, rem(i, length(lines)))
    body = if rem(i, 50) == 0, do: body <> "\n\n![photo](#{Uploads.url(upload)})", else: body
    {:ok, m} = Forum.post_message(author, topic, %{"body" => body})
    m
  end

for {m, i} <- Enum.with_index(Enum.take_every(messages, 7)) do
  Reactions.toggle(Enum.at(people, rem(i + 1, 7)), m, "+1")
end

IO.puts("TOPIC /t/#{topic.id}/#{topic.slug}")
