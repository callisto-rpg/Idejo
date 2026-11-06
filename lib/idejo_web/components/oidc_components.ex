# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OIDCComponents do
  @moduledoc """
  The "Sign in with …" button of the OpenID Connect provider (AC-09), on the sign-in and
  sign-up pages. A plain link: it works without JavaScript.
  """
  use IdejoWeb, :html

  alias Idejo.Accounts.OIDC

  attr :id, :string, default: "oidc-sign-in"
  attr :invite, :string, default: nil, doc: "an invite code to carry through the provider"
  attr :sign_up, :boolean, default: false

  def oidc_button(assigns) do
    assigns = assign(assigns, label: OIDC.label(), create_url: OIDC.sign_up_url())

    ~H"""
    <a
      :if={@label}
      id={@id}
      href={~p"/users/oidc?#{if(@invite, do: [invite: @invite], else: [])}"}
      class="btn btn-primary w-full"
    >
      <.icon name="hero-arrow-right-end-on-rectangle" class="size-5" />
      {if @sign_up,
        do: gettext("Sign up with %{provider}", provider: @label),
        else: gettext("Sign in with %{provider}", provider: @label)}
    </a>
    <p :if={@label && @create_url} id={@id <> "-create"} class="text-sm text-center">
      {gettext("No %{provider} yet?", provider: @label)}
      <a href={@create_url} class="link">{gettext("Create one")}</a>
    </p>
    """
  end
end
