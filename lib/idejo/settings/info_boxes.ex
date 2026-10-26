# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.InfoBoxes do
  @moduledoc """
  Info boxes (steward decision, 2026-10-25): cards of the administrators' own Markdown,
  shown to everyone beside the home page's categories, made in **Admin → Info boxes**.
  Every change is audited (`info_box.create|update|reorder|delete`, SP-06).
  """
  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Messages.Body
  alias Idejo.Repo
  alias Idejo.Settings.InfoBox

  @doc "The info boxes, in their order."
  @spec list() :: [InfoBox.t()]
  def list, do: Repo.all(from b in InfoBox, order_by: [asc: b.position, asc: b.created_at])

  @doc "Returns a changeset for an info box's form."
  def change(box \\ %InfoBox{}, attrs \\ %{}), do: InfoBox.changeset(box, attrs)

  @doc "Creates an info box at the end of the order, as `admin`."
  @spec create(User.t(), map()) :: {:ok, InfoBox.t()} | {:error, Ecto.Changeset.t()}
  def create(%User{} = admin, attrs) do
    Repo.transact(fn ->
      lock()
      position = Repo.aggregate(InfoBox, :count)

      with {:ok, box} <-
             %InfoBox{position: position}
             |> InfoBox.changeset(attrs)
             |> rendered(admin)
             |> Repo.insert(),
           {:ok, _} <- Audit.record(admin, "info_box.create", nil, snapshot(box)) do
        {:ok, box}
      end
    end)
  end

  @doc "Changes an info box's title, look or text, as `admin`."
  @spec update(User.t(), InfoBox.t(), map()) :: {:ok, InfoBox.t()} | {:error, Ecto.Changeset.t()}
  def update(%User{} = admin, %InfoBox{} = box, attrs) do
    Repo.transact(fn ->
      lock()

      with {:ok, updated} <- box |> InfoBox.changeset(attrs) |> rendered(admin) |> Repo.update(),
           {:ok, _} <- Audit.record(admin, "info_box.update", snapshot(box), snapshot(updated)) do
        {:ok, updated}
      end
    end)
  end

  @doc "Moves an info box one place up or down, as `admin`; `{:error, :at_edge}` at the ends."
  @spec move(User.t(), InfoBox.t(), :up | :down) :: {:ok, [InfoBox.t()]} | {:error, :at_edge}
  def move(%User{} = admin, %InfoBox{} = box, direction) when direction in [:up, :down] do
    Repo.transact(fn ->
      lock()
      boxes = list()

      case neighbours(boxes, box, direction) do
        {a, b} -> swap(admin, boxes, a, b)
        nil -> {:error, :at_edge}
      end
    end)
  end

  # The box and the one it swaps with, or nil at the edge (or when it is gone).
  defp neighbours(boxes, box, direction) do
    with index when is_integer(index) <- Enum.find_index(boxes, &(&1.id == box.id)),
         target = if(direction == :up, do: index - 1, else: index + 1),
         true <- target >= 0 and target < length(boxes) do
      {Enum.at(boxes, index), Enum.at(boxes, target)}
    else
      _ -> nil
    end
  end

  # Positions are renumbered from the list, so boxes made in the same second keep an order.
  defp swap(admin, before, a, b) do
    order = Enum.map(before, &if(&1.id == a.id, do: b, else: if(&1.id == b.id, do: a, else: &1)))

    for {box, position} <- Enum.with_index(order), box.position != position do
      {:ok, _} = Repo.update(Ecto.Changeset.change(box, position: position))
    end

    after_ = list()
    titles = &Enum.map(&1, fn box -> box.title end)

    {:ok, _} =
      Audit.record(admin, "info_box.reorder", %{"order" => titles.(before)}, %{
        "order" => titles.(after_)
      })

    {:ok, after_}
  end

  @doc "Deletes an info box, as `admin`."
  @spec delete(User.t(), InfoBox.t()) :: {:ok, InfoBox.t()} | {:error, term()}
  def delete(%User{} = admin, %InfoBox{} = box) do
    Repo.transact(fn ->
      lock()

      with {:ok, deleted} <- Repo.delete(box),
           {_, _} <-
             Repo.update_all(from(b in InfoBox, where: b.position > ^box.position),
               inc: [position: -1]
             ),
           {:ok, _} <- Audit.record(admin, "info_box.delete", snapshot(box), nil) do
        {:ok, deleted}
      end
    end)
  end

  @doc "The HTML of an info box's Markdown, with its inline links (TP-10) as `admin` sees them."
  @spec to_html(String.t(), User.t()) :: String.t()
  def to_html(markdown, %User{} = admin), do: Body.to_html(markdown, author: admin)

  # FD-03: the Markdown and its sanitised HTML, stored together.
  defp rendered(%{valid?: true} = changeset, admin) do
    Ecto.Changeset.put_change(
      changeset,
      :body_html,
      to_html(Ecto.Changeset.get_field(changeset, :body_md), admin)
    )
  end

  defp rendered(changeset, _admin), do: changeset

  defp snapshot(box),
    do: Audit.snapshot(box, [:title, :icon, :colour, :body_md, :show_head, :position])

  defp lock, do: Repo.query!("LOCK TABLE info_boxes IN SHARE ROW EXCLUSIVE MODE")
end
