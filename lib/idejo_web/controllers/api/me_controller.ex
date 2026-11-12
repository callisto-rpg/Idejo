# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.MeController do
  @moduledoc """
  The signed-in user's own account (AP-09, AP-12): what Profile and account does, through
  the same context functions: display name, user tag, bio, Writing, private messages,
  password, pictures, email summary and push choices, signed-in devices, self-select roles,
  the welcome card, warnings, ignored users and the community menu.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.{Access, Accounts, Community, Push}
  alias Idejo.Accounts.ApiTokens
  alias Idejo.Moderation.Warnings
  alias Idejo.Notifications.Digest

  def show(conn, _params), do: json(conn, Api.me(user(conn)))

  @doc """
  `display_name` and `user_tag` (`Accounts.update_user_profile/2`), `bio_md`
  (`update_user_bio/2`), `auto_punctuation` (`update_user_writing/2`),
  `accepts_private_messages` (`update_user_private_messages/2`): each saved by its own
  function, in that order; the first refusal stops.
  """
  def update(conn, params) do
    steps = [
      {~w(display_name user_tag), &Accounts.update_user_profile/2},
      {~w(bio_md),
       fn user, attrs -> Accounts.update_user_bio(user, %{"bio_md" => attrs["bio_md"] || ""}) end},
      {~w(auto_punctuation), &Accounts.update_user_writing/2},
      {~w(accepts_private_messages), &Accounts.update_user_private_messages/2}
    ]

    result =
      Enum.reduce_while(steps, {:ok, user(conn)}, fn {keys, save}, {:ok, user} ->
        case Map.take(params, keys) do
          attrs when attrs == %{} -> {:cont, {:ok, user}}
          attrs -> user |> save.(attrs) |> continue()
        end
      end)

    with {:ok, user} <- result, do: json(conn, Api.me(Accounts.get_user!(user.id)))
  end

  defp continue({:ok, user}), do: {:cont, {:ok, user}}
  defp continue(error), do: {:halt, error}

  @doc """
  The password (AC-01): `current_password`, `password`, `password_confirmation`. Every
  browser session and every device of the account, this one too, signs in again.
  """
  def password(conn, params) do
    attrs = Map.take(params, ~w(current_password password password_confirmation))

    with {:ok, {_user, socket_ids}} <- Accounts.update_user_password(user(conn), attrs, "") do
      IdejoWeb.UserAuth.disconnect_sessions(socket_ids)
      no_content(conn)
    end
  end

  def avatar(conn, params), do: set_avatar(conn, params, :light)
  def avatar_dark(conn, params), do: set_avatar(conn, params, :dark)

  defp set_avatar(conn, %{"image" => %Plug.Upload{path: path}}, theme) do
    with {:ok, user} <- Accounts.set_avatar(user(conn), path, theme), do: json(conn, Api.me(user))
  end

  defp set_avatar(_conn, _params, _theme), do: {:error, :bad_request}

  def delete_avatar(conn, _params), do: remove_avatar(conn, :light)
  def delete_avatar_dark(conn, _params), do: remove_avatar(conn, :dark)

  defp remove_avatar(conn, theme) do
    {:ok, user} = Accounts.remove_avatar(user(conn), theme)
    json(conn, Api.me(user))
  end

  def notification_settings(conn, _params), do: json(conn, settings(user(conn)))

  @doc "`email`: the email summary's choices (NO-04); `push`: the push types (PN-11)."
  def update_notification_settings(conn, params) do
    user = user(conn)

    with {:ok, _} <- maybe(params["email"], &Digest.update_preferences(user, &1)),
         {:ok, _} <- maybe(params["push"], &Push.update_preferences(user, &1)) do
      json(conn, settings(user))
    end
  end

  defp maybe(attrs, save) when is_map(attrs), do: save.(attrs)
  defp maybe(nil, _save), do: {:ok, nil}
  defp maybe(_attrs, _save), do: {:error, :bad_request}

  defp settings(user) do
    email = Digest.preferences(user)
    push = Push.preferences(user)

    %{
      "email" =>
        Map.new(
          ~w(mentions role_mentions own_topics followed_topics new_topics all_activity once_a_week)a,
          &{Atom.to_string(&1), Map.fetch!(email, &1)}
        ),
      "push" =>
        Map.new(
          ~w(reply mention role_mention followed private)a,
          &{Atom.to_string(&1), Map.fetch!(push, &1)}
        )
    }
  end

  def tokens(conn, _params) do
    current = conn.assigns.api_token.id

    send_list(
      conn,
      for token <- ApiTokens.list(user(conn)) do
        %{
          "id" => token.id,
          "name" => token.name,
          "scopes" => token.scopes,
          "signed_in_at" => Api.time(token.inserted_at),
          "last_used_at" => Api.time(token.last_used_at),
          "current" => token.id == current
        }
      end
    )
  end

  def delete_token(conn, %{"id" => id}) do
    with :ok <- ApiTokens.revoke(user(conn), id), do: no_content(conn)
  end

  def add_role(conn, %{"id" => id}), do: self_roles(conn, &[id | &1])
  def remove_role(conn, %{"id" => id}), do: self_roles(conn, &List.delete(&1, id))

  # Only self-select roles change (`Access.set_self_roles/2`); an unknown id changes nothing.
  defp self_roles(conn, change) do
    user = user(conn)
    selectable = MapSet.new(Access.self_select_roles(), & &1.id)

    held =
      for role <- Access.assigned_roles(user), MapSet.member?(selectable, role.id), do: role.id

    {:ok, _roles} = Access.set_self_roles(user, change.(held))
    json(conn, Api.me(Accounts.get_user!(user.id)))
  end

  def welcome(conn, _params) do
    {:ok, user} = Accounts.mark_welcomed(user(conn))
    json(conn, Api.me(user))
  end

  def warnings(conn, _params) do
    send_list(
      conn,
      for warning <- Warnings.pending(user(conn)) do
        %{
          "id" => warning.id,
          "reason" => warning.reason,
          "message_id" => warning.message_id,
          "category_id" => warning.category_id,
          "created_at" => Api.time(warning.created_at),
          "moderator" => nil
        }
      end
    )
  end

  def acknowledge_warnings(conn, _params) do
    :ok = Warnings.acknowledge(user(conn))
    no_content(conn)
  end

  def ignored(conn, _params),
    do: send_list(conn, Enum.map(Accounts.list_ignored(user(conn)), &Api.person/1))

  def communities(conn, _params) do
    send_list(
      conn,
      for community <- Community.communities(user(conn)) do
        %{"name" => community.name, "url" => community.url, "logo_url" => community.url <> "logo"}
      end
    )
  end
end
