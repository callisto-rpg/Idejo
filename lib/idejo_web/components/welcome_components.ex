# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WelcomeComponents do
  @moduledoc """
  The welcome card and "Rules & Roles" (steward decision, 2026-10-23): the server's About and
  Rules (Markdown from **Admin → Settings**), and the self-select roles a signed-in member
  gives themselves (`Idejo.Access.set_self_roles/2`) with a plain form posting to `/welcome`,
  so it works without JavaScript. The card shows once, on a new member's first visit
  (`Layouts.app`); the `/rules` page shows the same at any time.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext
  use IdejoWeb, :verified_routes

  alias Idejo.Access
  alias Idejo.Messages.Body
  alias Idejo.Settings
  alias IdejoWeb.Admin
  alias IdejoWeb.MessageComponents

  @doc "What the card and the page show, worked out for `user` (nil for a visitor)."
  @spec welcome_data(Idejo.Accounts.User.t() | nil) :: map()
  def welcome_data(user) do
    held = if user, do: MapSet.new(Access.roles_of(user), & &1.id), else: MapSet.new()

    %{
      roles: Access.self_select_roles(),
      held: held,
      about: Settings.get(:server_about),
      rules: Settings.get(:server_rules),
      signed_in?: user != nil
    }
  end

  attr :data, :map, required: true, doc: "from `welcome_data/1`"
  attr :heading, :string, values: ~w(h2 h3), default: "h2"

  attr :heading_class, :string,
    default: "welcome-heading",
    doc: "About's and Rules' look: small labels in the card, `heading-h1` on the page"

  attr :return_to, :string, default: nil
  attr :submit, :string, required: true
  attr :id, :string, default: "welcome", doc: "prefix of the ids, unique on the page"

  @doc "About, Rules and the self-select roles, in that order of reading."
  def welcome_content(assigns) do
    ~H"""
    <section :if={@data.about != ""} class="welcome-section" aria-labelledby={"#{@id}-about"}>
      <.dynamic_tag tag_name={@heading} id={"#{@id}-about"} class={@heading_class}>
        {gettext("About")}
      </.dynamic_tag>
      <MessageComponents.body html={Body.to_html(@data.about)} />
    </section>
    <section :if={@data.rules != ""} class="welcome-section" aria-labelledby={"#{@id}-rules"}>
      <.dynamic_tag tag_name={@heading} id={"#{@id}-rules"} class={@heading_class}>
        {gettext("Rules")}
      </.dynamic_tag>
      <MessageComponents.body html={Body.to_html(@data.rules)} />
    </section>
    <form
      :if={@data.signed_in?}
      action={~p"/welcome"}
      method="post"
      id={"#{@id}-form"}
      class="welcome-section"
    >
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />
      <fieldset :if={@data.roles != []}>
        <legend class="welcome-heading">{gettext("Add roles")}</legend>
        <p class="welcome-hint">
          {gettext("Pick the roles that fit you. You can change them later.")}
        </p>
        <input type="hidden" name="role_ids[]" value="" />
        <div class="welcome-roles">
          <label :for={role <- @data.roles} class="welcome-role">
            <input
              type="checkbox"
              name="role_ids[]"
              value={role.id}
              checked={MapSet.member?(@data.held, role.id)}
              class="checkbox checkbox-sm"
            />
            <Admin.role_label role={role} />
          </label>
        </div>
      </fieldset>
      <button class="btn btn-primary" autofocus>{@submit}</button>
    </form>
    """
  end
end
