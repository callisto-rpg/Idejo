# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.Controller do
  @moduledoc """
  What every API controller shares (AP-11, AP-17, AP-18): `use IdejoWeb.Api.Controller`.

  Controllers hold no rules: they read parameters, call one context function with the
  token's user first, and send what it answers. Returning `{:error, code}` (or `{:error,
  code, details}`, or an `Ecto.Changeset`) from an action sends the error shape
  (`IdejoWeb.Api.FallbackController`).

  Pages (AP-18): `?cursor=…&limit=…`, 50 by default, 100 at most; answers
  `{"data": [...], "next_cursor": …, "prev_cursor": …}`. Cursors are opaque, signed, and
  name the list they belong to.
  """

  alias Idejo.Forum
  alias Idejo.Forum.Topic

  defmacro __using__(_opts) do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      import IdejoWeb.Api.Controller
      alias Idejo.Api
      action_fallback IdejoWeb.Api.FallbackController
    end
  end

  @default_limit 50
  @max_limit 100
  @salt "api cursor"

  @doc "The token's user."
  @spec user(Plug.Conn.t()) :: Idejo.Accounts.User.t() | nil
  def user(conn), do: conn.assigns[:current_user]

  @doc "The page size asked for: 1 to #{@max_limit}, #{@default_limit} by default."
  @spec limit(map()) :: pos_integer()
  def limit(params) do
    case Integer.parse(to_string(params["limit"] || "")) do
      {n, ""} -> n |> max(1) |> min(@max_limit)
      _ -> @default_limit
    end
  end

  @doc "A signed cursor for `list` at `value`."
  @spec cursor(term(), term()) :: String.t()
  def cursor(list, value),
    do: Phoenix.Token.sign(IdejoWeb.Endpoint, @salt, {list, value})

  @doc "The value of a cursor for `list`: `{:ok, value}`, `:none` without one, or `:error`."
  @spec read_cursor(map(), term()) :: {:ok, term()} | :none | :error
  def read_cursor(%{"cursor" => cursor}, list) when is_binary(cursor) and cursor != "" do
    case Phoenix.Token.verify(IdejoWeb.Endpoint, @salt, cursor, max_age: :infinity) do
      {:ok, {^list, value}} -> {:ok, value}
      _ -> :error
    end
  end

  def read_cursor(_params, _list), do: :none

  @doc "The page number a page cursor stands for (1 without one); nil for a bad cursor."
  @spec page_number(map(), term()) :: pos_integer() | nil
  def page_number(params, list) do
    case read_cursor(params, list) do
      {:ok, page} when is_integer(page) and page > 0 -> page
      :none -> 1
      _ -> nil
    end
  end

  @doc "Sends a page: the items, and cursors to the next and previous pages (nil at the ends)."
  @spec send_page(Plug.Conn.t(), list(), String.t() | nil, String.t() | nil) :: Plug.Conn.t()
  def send_page(conn, data, next, prev \\ nil),
    do:
      Phoenix.Controller.json(conn, %{
        "data" => data,
        "next_cursor" => next,
        "prev_cursor" => prev
      })

  @doc "A numbered page's cursors."
  @spec page_cursors(term(), pos_integer(), boolean()) :: {String.t() | nil, String.t() | nil}
  def page_cursors(list, page, more?) do
    {if(more?, do: cursor(list, page + 1)), if(page > 1, do: cursor(list, page - 1))}
  end

  @doc "Sends `{\"data\": list}`."
  @spec send_list(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def send_list(conn, data), do: Phoenix.Controller.json(conn, %{"data" => data})

  @doc "204, no body."
  @spec no_content(Plug.Conn.t()) :: Plug.Conn.t()
  def no_content(conn), do: Plug.Conn.send_resp(conn, 204, "")

  @doc """
  The topic `id` the user may read: one they may view, or a private conversation of theirs,
  which also needs the token's `private` scope (AP-10). `{:error, :not_found}` otherwise,
  the same for a missing one (AP-17).
  """
  @spec readable_topic(Plug.Conn.t(), term()) ::
          {:ok, Topic.t()} | {:error, :not_found | :insufficient_scope}
  def readable_topic(conn, id) when is_binary(id) do
    case Forum.get_readable_topic(user(conn), id) do
      nil -> {:error, :not_found}
      %Topic{} = topic -> private_scope(conn, topic)
    end
  end

  def readable_topic(_conn, _id), do: {:error, :not_found}

  @doc "A topic the user may view (never a private conversation), or `{:error, :not_found}`."
  @spec viewable_topic(Plug.Conn.t(), term()) :: {:ok, Topic.t()} | {:error, :not_found}
  def viewable_topic(conn, id) when is_binary(id) do
    case Forum.get_viewable_topic(user(conn), id) do
      nil -> {:error, :not_found}
      topic -> {:ok, topic}
    end
  end

  def viewable_topic(_conn, _id), do: {:error, :not_found}

  @doc """
  The message `id` the user may read (`Forum.get_readable_message/2`), with the `private`
  scope when it is in a private conversation.
  """
  @spec readable_message(Plug.Conn.t(), term()) ::
          {:ok, Idejo.Messages.Message.t()} | {:error, :not_found | :insufficient_scope}
  def readable_message(conn, id) when is_binary(id) do
    case Forum.get_readable_message(user(conn), id) do
      nil ->
        {:error, :not_found}

      message ->
        with {:ok, _topic} <- private_scope(conn, message.topic), do: {:ok, message}
    end
  end

  def readable_message(_conn, _id), do: {:error, :not_found}

  defp private_scope(conn, %Topic{private: true} = topic) do
    if "private" in conn.assigns.api_token.scopes,
      do: {:ok, topic},
      else: {:error, :insufficient_scope}
  end

  defp private_scope(_conn, topic), do: {:ok, topic}

  @doc "A string parameter, trimmed; nil when missing or not a string."
  @spec string(map(), String.t()) :: String.t() | nil
  def string(params, key) do
    case params[key] do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  @doc "A boolean parameter (JSON true or \"true\"), else `default`."
  @spec boolean(map(), String.t(), boolean()) :: boolean()
  def boolean(params, key, default \\ false) do
    case params[key] do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> default
    end
  end
end
