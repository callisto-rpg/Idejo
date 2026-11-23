# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.TopicIcons do
  @moduledoc """
  The topic icons (Topic Type, steward request, 2026-11-07): the set administrators upload
  in **Admin → Topic icons**, offered in a dialog when a topic starts in a topical category
  and to moderators changing a topical topic's icon. Each change is audited (SP-06).
  Deleting an icon leaves the topics that showed it with none (the category's mark).

  Any Twemoji emoji may be chosen too (steward request, 2026-11-24): `for_emoji/1` gives its
  icon, made at its first use; emoji icons are not in the set (`list/0`) but are in
  `index/0` and `get/1`, and draw from `Idejo.Emoji`'s image.
  """
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Emoji
  alias Idejo.Forum.TopicIcon
  alias Idejo.Repo
  alias Idejo.Uploads

  @doc "The administrators' icons, in their order, with their upload (no emoji)."
  @spec list() :: [TopicIcon.t()]
  def list do
    Repo.all(
      from i in TopicIcon,
        where: is_nil(i.emoji),
        order_by: [asc: i.position, asc: i.created_at],
        preload: :upload
    )
  end

  @doc """
  Every icon by id, with its upload: read once per request or mount (`Idejo.Memo`), so a
  list of topical topics costs one query.
  """
  @spec index() :: %{String.t() => TopicIcon.t()}
  def index do
    Idejo.Memo.fetch(:topic_icons, fn ->
      Map.new(Repo.all(from i in TopicIcon, preload: :upload), &{&1.id, &1})
    end)
  end

  @doc """
  The icon of a Twemoji emoji, by its name (`"joy"`), made at its first use; the server's own
  reactions are not Twemoji and give `:error`.
  """
  @spec for_emoji(String.t()) :: {:ok, TopicIcon.t()} | :error
  def for_emoji(name) when is_binary(name) do
    case Emoji.lookup(name) do
      %{char: char, name: name} when is_binary(char) ->
        row = %{
          id: Ecto.UUID.generate(),
          emoji: name,
          name: String.replace(name, "_", " "),
          created_at: DateTime.utc_now(:second)
        }

        Repo.insert_all(TopicIcon, [row], on_conflict: :nothing, conflict_target: :emoji)

        {:ok, Repo.get_by!(TopicIcon, emoji: name)}

      _ ->
        :error
    end
  end

  def for_emoji(_name), do: :error

  @doc "Whether `id` is an emoji's icon."
  @spec emoji?(String.t() | nil) :: boolean()
  def emoji?(id) do
    case Ecto.UUID.cast(id || "") do
      {:ok, id} -> Repo.exists?(from i in TopicIcon, where: i.id == ^id and not is_nil(i.emoji))
      :error -> false
    end
  end

  @doc "An icon by id, with its upload, or nil."
  @spec get(String.t() | nil) :: TopicIcon.t() | nil
  def get(nil), do: nil

  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> TopicIcon |> Repo.get(id) |> Repo.preload(:upload)
      :error -> nil
    end
  end

  @doc "A changeset for the upload form."
  @spec change(map()) :: Ecto.Changeset.t()
  def change(attrs \\ %{}), do: TopicIcon.changeset(%TopicIcon{}, attrs)

  @doc """
  Adds an icon: the image at `path` (`Uploads.store_icon/2`) named `attrs["name"]`, last in
  the order. Audited as `topic_icon.create`.
  """
  @spec create(User.t(), Path.t(), map()) ::
          {:ok, TopicIcon.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create(%User{} = admin, path, attrs),
    do: Idejo.Access.as_administrator(admin, fn -> as_admin_insert_icon(admin, path, attrs) end)

  defp as_admin_insert_icon(%User{} = admin, path, attrs) do
    changeset = change(attrs)

    with true <- changeset.valid? || {:error, %{changeset | action: :insert}},
         {:ok, upload} <- Uploads.store_icon(admin, path) do
      Repo.transact(fn -> insert(admin, changeset, upload) end)
    end
  end

  defp insert(admin, changeset, upload) do
    position = Repo.one(from i in TopicIcon, select: coalesce(max(i.position), 0)) + 1

    with {:ok, icon} <-
           changeset
           |> Ecto.Changeset.put_change(:upload_id, upload.id)
           |> Ecto.Changeset.put_change(:position, position)
           |> Repo.insert(),
         {:ok, _} <- Audit.record(admin, "topic_icon.create", nil, snapshot(icon)) do
      {:ok, Repo.preload(icon, :upload)}
    end
  end

  @doc """
  Adds an icon the server ships (the onboarding topic's waving hand, `Idejo.Onboarding`):
  the image at `path`, named `name`, last in the order, stored as `user`'s (an administrator
  or a server account). Audited as `topic_icon.create`; afterwards it is like any other.
  """
  @spec add_bundled(User.t(), Path.t(), String.t()) ::
          {:ok, TopicIcon.t()} | {:error, Ecto.Changeset.t() | atom()}
  def add_bundled(%User{} = user, path, name) do
    changeset = change(%{"name" => name})

    with true <- changeset.valid? || {:error, %{changeset | action: :insert}},
         {:ok, upload} <- Uploads.store_icon(user, path) do
      Repo.transact(fn -> insert(user, changeset, upload) end)
    end
  end

  @doc "Deletes an icon; its topics show none. Audited as `topic_icon.delete`."
  @spec delete(User.t(), TopicIcon.t()) :: {:ok, TopicIcon.t()} | {:error, Ecto.Changeset.t()}
  def delete(%User{} = admin, %TopicIcon{} = icon),
    do: Idejo.Access.as_administrator(admin, fn -> as_admin_delete_icon(admin, icon) end)

  defp as_admin_delete_icon(%User{} = admin, %TopicIcon{} = icon) do
    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(icon),
           {:ok, _} <- Audit.record(admin, "topic_icon.delete", snapshot(icon), nil) do
        {:ok, deleted}
      end
    end)
  end

  @doc "The icon's image address, or nil for none."
  @spec url(TopicIcon.t() | nil) :: String.t() | nil
  def url(nil), do: nil
  def url(%TopicIcon{emoji: emoji}) when is_binary(emoji), do: Emoji.lookup(emoji)[:src]
  def url(%TopicIcon{upload: %Uploads.Upload{} = upload}), do: Uploads.url(upload)

  def url(%TopicIcon{} = icon), do: icon |> Repo.preload(:upload) |> url()

  defp snapshot(icon), do: %{"name" => icon.name, "upload_id" => icon.upload_id}
end
