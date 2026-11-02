# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OIDCController do
  @moduledoc """
  Sign-in through the OpenID Connect provider (AC-09, `Idejo.Accounts.OIDC`).

  `GET /users/oidc` starts it: `intent` `sign_in` (the default; an `invite` code is carried
  through the provider), `link` (a signed-in member links their account from the profile)
  or `reauth` (a signed-in member confirms deleting their account). The request's `state`,
  `nonce` and PKCE verifier wait in the encrypted session, used once.
  `GET /users/oidc/callback` is where the provider sends the browser back. 404 while
  OpenID Connect is not set up.
  """
  use IdejoWeb, :controller

  require Logger

  alias Idejo.Accounts
  alias Idejo.Accounts.OIDC
  alias IdejoWeb.UserAuth

  # SP-05: each callback is a sign-in attempt.
  plug IdejoWeb.Plugs.RateLimit, :sign_in when action == :callback
  plug :require_oidc

  @session_key "oidc_request"
  @intents ~w(sign_in link reauth)

  def start(conn, params) do
    intent = if params["intent"] in @intents, do: params["intent"], else: "sign_in"
    user = current_user(conn)

    cond do
      intent != "sign_in" and is_nil(user) ->
        redirect(conn, to: ~p"/users/sign-in")

      intent == "sign_in" and user ->
        redirect(conn, to: ~p"/")

      true ->
        request = OIDC.new_request(intent, blank_to_nil(params["invite"]))

        case OIDC.authorize_url(request, redirect_uri()) do
          {:ok, url} ->
            conn |> put_session(@session_key, request) |> redirect(external: url)

          {:error, reason} ->
            Logger.warning("OpenID Connect: no sign-in address: #{reason_tag(reason)}")

            conn
            |> put_flash(
              :error,
              gettext("%{provider} cannot be reached right now. Please try again in a moment.",
                provider: OIDC.label()
              )
            )
            |> redirect(to: back(intent))
        end
    end
  end

  def callback(conn, params) do
    request = get_session(conn, @session_key)
    conn = delete_session(conn, @session_key)
    intent = (request || %{})["intent"] || "sign_in"

    case OIDC.claims(request, params, redirect_uri()) do
      {:ok, claims} ->
        finish(conn, intent, claims, request)

      {:error, reason} ->
        # The reason is for the operator; the person only learns it did not work.
        Logger.warning("OpenID Connect: sign-in refused: #{reason_tag(reason)}")

        conn
        |> put_flash(
          :error,
          gettext("Signing in with %{provider} did not work. Please try again.",
            provider: OIDC.label()
          )
        )
        |> redirect(to: back(intent))
    end
  end

  defp finish(conn, "sign_in", claims, request) do
    case OIDC.sign_in(claims, request["invite"]) do
      {:ok, user, kind} ->
        log_in(conn, user, kind)

      {:error, reason} ->
        conn |> put_flash(:error, refusal(reason)) |> redirect(to: back("sign_in"))
    end
  end

  defp finish(conn, "link", claims, _request) do
    user = current_user(conn)

    message =
      case user && OIDC.link(user, claims) do
        {:ok, _identity} ->
          {:info, gettext("Your account is now linked to %{provider}.", provider: OIDC.label())}

        {:error, :taken} ->
          {:error,
           gettext("That %{provider} account is already linked to another account here.",
             provider: OIDC.label()
           )}

        {:error, :already_linked} ->
          {:error,
           gettext("Your account is already linked to another %{provider} account.",
             provider: OIDC.label()
           )}

        nil ->
          {:error, gettext("Sign in first.")}
      end

    conn |> put_flash(elem(message, 0), elem(message, 1)) |> redirect(to: back("link"))
  end

  defp finish(conn, "reauth", claims, _request) do
    user = current_user(conn)

    case OIDC.find_user(claims) do
      %{id: id} when user != nil and id == user.id ->
        conn
        |> put_session("oidc_reauth_at", System.system_time(:second))
        |> put_flash(
          :info,
          gettext("Confirmed. You can delete your account in the next five minutes.")
        )
        |> redirect(to: ~p"/users/settings#delete-heading")

      _ ->
        conn
        |> put_flash(
          :error,
          gettext("That is not the %{provider} account linked to yours.", provider: OIDC.label())
        )
        |> redirect(to: back("reauth"))
    end
  end

  # As the password sign-in does: a ban is told only once the person is who they say.
  defp log_in(conn, user, kind) do
    cond do
      user.status != "active" ->
        conn
        |> put_flash(:error, refusal(:inactive))
        |> redirect(to: ~p"/users/sign-in")

      Accounts.banned?(user) ->
        conn
        |> put_flash(:error, IdejoWeb.UserSessionController.banned_message(user))
        |> redirect(to: ~p"/users/sign-in")

      true ->
        conn
        |> put_flash(:info, welcome(user, kind))
        |> UserAuth.log_in_user(user)
    end
  end

  defp welcome(user, :unverified) do
    case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}")) do
      {:ok, _} ->
        gettext("Welcome! We sent a link to %{email}; open it to verify your email address.",
          email: user.email
        )

      {:error, _} ->
        gettext(
          "Welcome! We could not send the verification email. Please try again in a moment."
        )
    end
  end

  defp welcome(_user, :new), do: gettext("Welcome!")
  defp welcome(_user, :existing), do: gettext("Welcome back!")

  defp refusal(:email_taken),
    do:
      gettext(
        "An account here already uses the email address %{provider} gave. Sign in with its password, then link %{provider} in Profile and account.",
        provider: OIDC.label()
      )

  defp refusal(:no_email),
    do:
      gettext("%{provider} did not give an email address, which an account here needs.",
        provider: OIDC.label()
      )

  defp refusal(:closed), do: gettext("This server is not taking new members.")

  defp refusal(:invite),
    do:
      gettext(
        "Joining is by invitation. Open the invite link you were given, then sign up with %{provider}.",
        provider: OIDC.label()
      )

  defp refusal(:inactive), do: gettext("This account cannot sign in.")

  defp refusal(%Ecto.Changeset{}),
    do: gettext("Your account could not be created. Please try again.")

  defp back("sign_in"), do: ~p"/users/sign-in"
  defp back(_intent), do: ~p"/users/settings"

  defp redirect_uri, do: url(~p"/users/oidc/callback")

  defp current_user(conn), do: conn.assigns[:current_scope] && conn.assigns.current_scope.user

  defp blank_to_nil(value) when is_binary(value) and value != "", do: String.trim(value)
  defp blank_to_nil(_value), do: nil

  # Only the kind of failure goes to the log: never a token, claim or secret.
  defp reason_tag(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_tag({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp reason_tag({tag, _, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp reason_tag(_reason), do: "other"

  defp require_oidc(conn, _opts) do
    if OIDC.enabled?() do
      conn
    else
      conn |> send_resp(404, "") |> halt()
    end
  end
end
