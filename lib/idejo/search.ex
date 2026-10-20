# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Search do
  @moduledoc """
  Full-text search (SE-01 to SE-03) in PostgreSQL, with the 'simple' configuration (steward
  decision): it works for any language, and matches words as written, without stemming.

  Each message is one document (SE-03, GM-13): `messages.search_vector` is a generated column
  over `body_md` (with `<` and `>` read as spaces, see the migration), so every commit
  re-indexes a growing message. A topic whose title matches is
  found through its first message. The query is read like a web search box
  (`websearch_to_tsquery`): `"quoted phrases"`, `or`, and `-excluded` words.

  Results only come from categories the searcher may view, filtered in the query (SE-02), and
  may be narrowed to one category.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Repo

  # ts_headline marks matches with these; `excerpt/1` turns them into marked segments, so no
  # HTML is ever built from message text.
  @start <<1>>
  @stop <<2>>
  @headline "StartSel=#{@start}, StopSel=#{@stop}, MaxWords=35, MinWords=15, MaxFragments=0"

  @type result :: %{message: Message.t(), excerpt: [{:text | :match, String.t()}]}

  @doc """
  Searches messages and topic titles as the user (`nil` for a visitor), best matches first,
  20 a page: `{results, more?}`. Each result has its message, with author and topic (with
  category), and an excerpt as segments, `{:match, text}` for the words found.

  ## Options

    * `:category` - a category to search in (one the user may view).
    * `:page` - from 1.
  """
  @spec search(User.t() | nil, String.t(), keyword()) :: {[result()], boolean()}
  def search(user, text, opts \\ []) when is_binary(text) do
    case String.trim(text) do
      "" -> {[], false}
      text -> run(user, text, opts)
    end
  end

  defp run(user, text, opts) do
    per_page = Keyword.get(opts, :per_page, 20)
    page = max(Keyword.get(opts, :page, 1), 1)
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    query =
      from m in Message,
        join: t in Topic,
        on: t.id == m.topic_id,
        where: t.category_id in subquery(viewable),
        where:
          fragment("? @@ websearch_to_tsquery('simple', ?)", m.search_vector, ^text) or
            (fragment(
               "to_tsvector('simple'::regconfig, ?) @@ websearch_to_tsquery('simple', ?)",
               t.title,
               ^text
             ) and
               fragment(
                 "? = (SELECT f.id FROM messages f WHERE f.topic_id = ? ORDER BY f.opened_at, f.id LIMIT 1)",
                 m.id,
                 t.id
               )),
        order_by: [
          desc:
            fragment(
              "ts_rank(?, websearch_to_tsquery('simple', ?)) + CASE WHEN to_tsvector('simple'::regconfig, ?) @@ websearch_to_tsquery('simple', ?) THEN 1 ELSE 0 END",
              m.search_vector,
              ^text,
              t.title,
              ^text
            ),
          desc: m.opened_at,
          desc: m.id
        ],
        offset: ^((page - 1) * per_page),
        limit: ^(per_page + 1),
        select:
          {m,
           fragment(
             "ts_headline('simple', translate(?, '<>', '  '), websearch_to_tsquery('simple', ?), ?)",
             m.body_md,
             ^text,
             ^@headline
           )}

    rows =
      query
      |> in_category(opts[:category])
      |> Repo.all()

    messages = rows |> Enum.map(&elem(&1, 0)) |> Repo.preload([:author, topic: :category])

    results =
      Enum.zip_with(messages, rows, fn message, {_, headline} ->
        %{message: message, excerpt: excerpt(headline)}
      end)

    {Enum.take(results, per_page), length(results) > per_page}
  end

  defp in_category(query, nil), do: query

  defp in_category(query, %Category{id: id}),
    do: where(query, [_m, t], t.category_id == ^id)

  @doc false
  # Splits a headline into plain and matched segments.
  @spec excerpt(String.t()) :: [{:text | :match, String.t()}]
  def excerpt(headline) do
    [first | rest] = String.split(headline, @start)

    rest
    |> Enum.flat_map(fn part ->
      case String.split(part, @stop, parts: 2) do
        [match, after_] -> [{:match, match}, {:text, after_}]
        [match] -> [{:match, match}]
      end
    end)
    |> then(&[{:text, first} | &1])
    |> Enum.reject(fn {_, s} -> s == "" end)
  end
end
