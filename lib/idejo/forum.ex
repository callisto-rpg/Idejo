# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum do
  @moduledoc """
  The forum structure: categories (RP-03), and topics from M2.

  Administrators create, rename, reorder and delete categories in **Admin → Categories**. Each
  change is audited (SP-06) and recorded as an activity (FD-02) in the same transaction.
  """

  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Federation
  alias Idejo.Forum.Category
  alias Idejo.Repo

  @doc """
  Lists the categories in their order.
  """
  @spec list_categories() :: [Category.t()]
  def list_categories do
    Repo.all(from c in Category, order_by: [asc: c.position, asc: c.name])
  end

  @doc """
  Gets a category by slug, or `nil`.
  """
  @spec get_category_by_slug(String.t()) :: Category.t() | nil
  def get_category_by_slug(slug) when is_binary(slug), do: Repo.get_by(Category, slug: slug)

  @doc """
  Returns a changeset for the new-category form.
  """
  def change_new_category(attrs \\ %{}), do: Category.create_changeset(%Category{}, attrs)

  @doc """
  Returns a changeset for the edit form.
  """
  def change_category(%Category{} = category, attrs \\ %{}),
    do: Category.update_changeset(category, attrs)

  @doc """
  Creates a category at the end of the order, as `admin`.

  Without a slug, one is made from the name ("Help & Support" becomes `help-support`, with
  `-2`, `-3`… added when taken). Audited as `category.create`, with a `create` activity.
  """
  @spec create_category(User.t(), map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create_category(%User{} = admin, attrs) do
    id = Federation.generate_id()

    Repo.transact(fn ->
      lock_categories()
      position = Repo.aggregate(Category, :count)

      attrs =
        attrs |> Map.new(fn {key, value} -> {to_string(key), value} end) |> put_default_slug()

      category = %Category{id: id, uri: Federation.uri(:category, id), position: position}

      with {:ok, category} <- Repo.insert(Category.create_changeset(category, attrs)),
           :ok <- record(admin, "create", nil, category) do
        {:ok, category}
      end
    end)
  end

  @doc """
  Renames a category or changes its description, as `admin`. The slug stays, so links keep
  working. Audited as `category.update`, with an `update` activity. Unchanged values write
  nothing.
  """
  @spec update_category(User.t(), Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%User{} = admin, %Category{} = category, attrs) do
    case Category.update_changeset(category, attrs) do
      %Ecto.Changeset{changes: changes} when changes == %{} -> {:ok, category}
      changeset -> Repo.transact(fn -> save_category(admin, category, changeset) end)
    end
  end

  defp save_category(admin, category, changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         :ok <- record(admin, "update", category, updated) do
      {:ok, updated}
    end
  end

  @doc """
  Moves a category one place up or down, as `admin`. Audited as `category.reorder` with the
  whole order before and after. Returns `{:error, :at_edge}` at the top or bottom.
  """
  @spec move_category(User.t(), Category.t(), :up | :down) ::
          {:ok, [Category.t()]} | {:error, :at_edge}
  def move_category(%User{} = admin, %Category{} = category, direction)
      when direction in [:up, :down] do
    Repo.transact(fn ->
      lock_categories()
      categories = list_categories()

      case neighbours(categories, category, direction) do
        {category, neighbour} -> swap(admin, categories, category, neighbour)
        nil -> {:error, :at_edge}
      end
    end)
  end

  defp neighbours(categories, category, direction) do
    with index when is_integer(index) <- Enum.find_index(categories, &(&1.id == category.id)),
         target = if(direction == :up, do: index - 1, else: index + 1),
         # Enum.at/2 counts negative indexes from the end, so stop at the top first.
         true <- target >= 0,
         %Category{} = neighbour <- Enum.at(categories, target) do
      {Enum.at(categories, index), neighbour}
    else
      _ -> nil
    end
  end

  defp swap(admin, before, category, neighbour) do
    with {:ok, _} <- Repo.update(Ecto.Changeset.change(category, position: neighbour.position)),
         {:ok, _} <- Repo.update(Ecto.Changeset.change(neighbour, position: category.position)),
         after_ = list_categories(),
         {:ok, _} <-
           Audit.record(admin, "category.reorder", %{"order" => slugs(before)}, %{
             "order" => slugs(after_)
           }) do
      {:ok, after_}
    end
  end

  defp slugs(categories), do: Enum.map(categories, & &1.slug)

  @doc """
  Deletes a category, as `admin`; the ones below move up. Audited as `category.delete`, with
  a `delete` activity.

  Categories hold no topics yet; when topics arrive (M2), deleting a category must first
  move or archive them (v1 RP-03).
  """
  @spec delete_category(User.t(), Category.t()) :: {:ok, Category.t()} | {:error, term()}
  def delete_category(%User{} = admin, %Category{} = category) do
    Repo.transact(fn ->
      lock_categories()

      with {:ok, deleted} <- Repo.delete(category),
           {_, _} <-
             Repo.update_all(from(c in Category, where: c.position > ^category.position),
               inc: [position: -1]
             ),
           :ok <- record(admin, "delete", category, nil) do
        {:ok, deleted}
      end
    end)
  end

  # One audit entry (SP-06) and one activity (FD-02) per change.
  defp record(admin, verb, before, after_) do
    object = after_ || before

    with {:ok, _} <-
           Audit.record(admin, "category." <> verb, snapshot(before), snapshot(after_)),
         {:ok, _} <-
           Repo.insert(
             Federation.activity_changeset(%{
               actor_uri: admin.uri,
               verb: verb,
               object_uri: object.uri,
               payload: %{"type" => "Group", "name" => object.name, "slug" => object.slug}
             })
           ) do
      :ok
    end
  end

  defp snapshot(nil), do: nil
  defp snapshot(category), do: Audit.snapshot(category, [:name, :slug, :description, :position])

  # A blank slug field means "make one from the name".
  defp put_default_slug(attrs) do
    case attrs["slug"] do
      slug when is_binary(slug) and slug != "" ->
        if String.trim(slug) == "", do: default_slug(attrs), else: attrs

      _ ->
        default_slug(attrs)
    end
  end

  defp default_slug(attrs),
    do: Map.put(attrs, "slug", free_slug(slugify(attrs["name"] || "")))

  @doc """
  Turns a name into a slug: lowercase ASCII letters and digits separated by single dashes.
  Accents are dropped ("Café" → `cafe`); a name with no letters or digits gives `category`.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(name) do
    slug =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)
      |> String.trim("-")

    if slug == "", do: "category", else: slug
  end

  defp free_slug(base) do
    taken =
      MapSet.new(Repo.all(from c in Category, where: like(c.slug, ^"#{base}%"), select: c.slug))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  # Positions are rewritten as a whole; one change at a time.
  defp lock_categories, do: Repo.query!("LOCK TABLE categories IN SHARE ROW EXCLUSIVE MODE")
end
