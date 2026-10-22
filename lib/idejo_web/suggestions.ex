# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Suggestions do
  @moduledoc """
  Suggestions while typing an inline link (TP-10), for the composer and the message editor:
  the `Suggest` code in `assets/js/suggest.js` pushes `"suggest"` with the sign and what
  follows it, and the LiveView answers with `reply/3`. Each item says what to insert after
  the sign (a username or a slug), and how to show it.
  """
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access
  alias Idejo.Suggestions

  @doc """
  The `{:reply, %{items: [...]}, socket}` for a `"suggest"` event: `%{"sign" => "@",
  "q" => "rob"}`. `opts` go to `Idejo.Suggestions.suggest/4` (`topic_id:`).
  """
  def reply(socket, params, opts \\ []) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    items =
      case Suggestions.kind(params["sign"] || "") do
        nil ->
          []

        kind ->
          user
          |> Suggestions.suggest(kind, to_string(params["q"] || ""), opts)
          |> Enum.map(&item(kind, &1))
      end

    {:reply, %{items: items}, socket}
  end

  defp item(:user, user),
    do: %{insert: user.username, label: user.display_name, detail: "@" <> user.username}

  defp item(:role, role) do
    slug = Access.role_slug(role)
    %{insert: slug, label: IdejoWeb.Admin.role_name(role), detail: "+" <> slug}
  end

  defp item(:topic, topic),
    do: %{
      insert: topic.slug,
      label: topic.title,
      detail: "#" <> topic.slug <> " · " <> topic.category.name
    }

  defp item(:category, category),
    do: %{insert: category.slug, label: category.name, detail: "/" <> category.slug}

  defp item(:tag, tag), do: %{insert: tag.slug, label: tag.name, detail: "$" <> tag.slug}

  @doc "The label of a suggestion list, for screen readers."
  def list_label, do: gettext("Suggestions")
end
