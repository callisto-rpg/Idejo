# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.CategoryController do
  @moduledoc "Categories and their topics (AP-12): what the home and category pages show."
  use IdejoWeb.Api.Controller

  alias Idejo.Forum
  alias Idejo.Forum.Category

  def index(conn, _params), do: send_list(conn, Api.categories(user(conn)))

  def show(conn, %{"id" => id}) do
    with {:ok, category} <- category(conn, id), do: json(conn, Api.category(user(conn), category))
  end

  def topics(conn, %{"id" => id} = params) do
    with {:ok, category} <- category(conn, id),
         page when is_integer(page) <-
           page_number(params, {:category, category.id}) || {:error, :bad_request} do
      {topics, more?} = Forum.list_topics(category, page: page, per_page: limit(params))
      {next, prev} = page_cursors({:category, category.id}, page, more?)

      send_page(
        conn,
        Api.topics(user(conn), topics, expanded: boolean(params, "expanded")),
        next,
        prev
      )
    end
  end

  def pending(conn, %{"id" => id}) do
    with {:ok, category} <- category(conn, id) do
      send_list(
        conn,
        Enum.map(Forum.list_own_pending_topics(user(conn), category), &pending_topic/1)
      )
    end
  end

  @doc false
  def pending_topic(pending) do
    %{
      "id" => pending.id,
      "title" => pending.title,
      "category_id" => pending.category_id,
      "body_md" => pending.body,
      "created_at" => Api.time(pending.created_at)
    }
  end

  @doc """
  Starts a topic (TP-01): `title`, `body_md`, `tag_ids`, and in a topical category
  `icon_id`; a moderator may ask `topical: true`. It may wait for approval (MO-04):
  `"pending"` then holds it.
  """
  def create_topic(conn, %{"id" => id} = params) do
    with {:ok, category} <- category(conn, id) do
      create(conn, category, params, [])
    end
  end

  @doc false
  def create(conn, category, params, opts) do
    attrs = %{
      "title" => params["title"],
      "body" => params["body_md"],
      "tag_ids" => List.wrap(params["tag_ids"]),
      "icon_id" => params["icon_id"],
      "topical" => to_string(params["topical"] == true)
    }

    case Forum.create_topic(user(conn), category, attrs, opts) do
      {:ok, topic} -> json(conn, %{"topic" => Api.topic(user(conn), topic), "pending" => nil})
      {:pending, pending} -> json(conn, %{"topic" => nil, "pending" => pending_topic(pending)})
      error -> error
    end
  end

  @doc false
  def category(conn, id) when is_binary(id) do
    case Enum.find(Forum.list_viewable_categories(user(conn)), &(&1.id == id)) do
      %Category{} = category -> {:ok, category}
      nil -> {:error, :not_found}
    end
  end

  def category(_conn, _id), do: {:error, :not_found}
end
