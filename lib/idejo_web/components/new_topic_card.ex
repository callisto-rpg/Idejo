# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NewTopicCard do
  @moduledoc """
  The card `!new-topic:Title:` opens over a topic, or `!new-topic` with no message to start
  from (steward request, 2026-11-13): a title, a category (the topic's by default, among those
  the member may start topics in), the first message, the category's tags when it offers any,
  and, for the category's moderators, the new topic's own permissions
  (`Idejo.Access.set_topic_permissions/3`). A topical category needs an icon: the card then
  leads to the New topic page instead.

  `IdejoWeb.TopicLive` keeps its state (`open/3`, `change/3`) and posts it (`create/3`).
  """
  use IdejoWeb, :html

  alias Idejo.{Access, Forum}
  alias Idejo.Forum.Tags
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}

  @type state :: %{
          params: map(),
          categories: [Category.t()],
          category: Category.t(),
          tags: list(),
          topical?: boolean(),
          permissions?: boolean(),
          permissions: map(),
          roles: list(),
          inherited: map(),
          errors: map()
        }

  @doc """
  The card's state for `user` over `topic`, with `title` filled in; nil when they may start
  no topic.
  """
  @spec open(User.t() | nil, Topic.t(), String.t() | nil) :: state() | nil
  def open(nil, _topic, _title), do: nil

  def open(%User{} = user, %Topic{} = topic, title) do
    case Forum.list_startable_categories(user) do
      [] ->
        nil

      categories ->
        category = Enum.find(categories, &(&1.id == topic.category_id)) || hd(categories)
        params = %{"title" => String.trim(title || ""), "body" => "", "tag_ids" => []}

        put_category(
          %{params: params, permissions: %{}, categories: categories, errors: %{}},
          user,
          category
        )
    end
  end

  @doc """
  The card's state after the form changed (the event's params: `new_topic` and
  `permissions`): the category chosen decides the rest.
  """
  @spec change(state(), User.t(), map()) :: state()
  def change(state, user, event_params) do
    params = if is_map(event_params["new_topic"]), do: event_params["new_topic"], else: %{}
    chosen = if is_map(event_params["permissions"]), do: event_params["permissions"], else: %{}

    category =
      Enum.find(state.categories, &(&1.id == params["category_id"])) || state.category

    state = %{state | params: Map.merge(state.params, params), permissions: chosen}
    if category.id == state.category.id, do: state, else: put_category(state, user, category)
  end

  @doc "A permission cell's value in the card: what was chosen, else `\"unset\"`."
  @spec chosen(state(), Ecto.UUID.t(), atom()) :: String.t()
  def chosen(state, role_id, right),
    do: get_in(state.permissions, [role_id, Atom.to_string(right)]) || "unset"

  @doc """
  Starts the topic from the card, then sets the permissions chosen (only for the category's
  moderators). `{:ok, topic}`, `{:pending, pending}` (MO-04: no permissions then), or
  `{:error, reason, state}` with the form's errors in the state.
  """
  @spec create(state(), User.t(), map()) ::
          {:ok, Topic.t()} | {:pending, term()} | {:error, term(), state()}
  def create(state, user, event_params) do
    state = change(state, user, event_params)
    attrs = Map.take(state.params, ["title", "body", "tag_ids"])

    case Forum.create_topic(user, state.category, attrs) do
      {:ok, topic} ->
        if state.permissions?, do: Access.set_topic_permissions(user, topic, state.permissions)
        {:ok, topic}

      {:pending, pending} ->
        {:pending, pending}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, :invalid, %{state | errors: errors(changeset)}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp put_category(state, user, category) do
    tags = Tags.available_tags(category)
    kept = Enum.map(tags, & &1.id)

    ids = state.params |> Map.get("tag_ids") |> List.wrap() |> Enum.filter(&(&1 in kept))
    params = Map.put(state.params, "tag_ids", ids)
    permissions? = Access.can?(user, :moderate, category)
    inherited = if permissions?, do: Access.category_rights(%Topic{category_id: category.id})

    Map.merge(state, %{
      params: Map.put(params, "category_id", category.id),
      category: category,
      tags: tags,
      topical?: category.topic_type == "topical",
      permissions?: permissions?,
      roles: if(permissions?, do: roles(), else: []),
      inherited: inherited || %{}
    })
  end

  # Owner and administrator always have every right: no setting to show.
  defp roles,
    do: Enum.reject(Access.list_roles(), &(&1.built_in and &1.name in ~w(owner administrator)))

  defp errors(changeset) do
    Map.new(changeset.errors, fn {field, error} -> {field, translate_error(error)} end)
  end

  attr :state, :map, required: true

  @doc """
  The card, a modal dialog (the InlineCard hook opens it and reports its closing as
  `hide_new_topic`); it sends `new_topic_change` and `create_new_topic`.
  """
  def dialog(assigns) do
    ~H"""
    <dialog
      id="new-topic-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_new_topic"
      aria-labelledby="new-topic-dialog-title"
    >
      <div class="modal-box new-topic-card">
        <h2 id="new-topic-dialog-title" class="inline-card-title">{gettext("New topic")}</h2>
        <.form
          for={%{}}
          id="new-topic-form"
          phx-change="new_topic_change"
          phx-submit="create_new_topic"
        >
          <label class="block">
            <span class="label mb-1">{gettext("Title")}</span>
            <input
              type="text"
              name="new_topic[title]"
              id="new-topic-title"
              value={@state.params["title"]}
              maxlength="150"
              required
              class="input w-full"
            />
          </label>
          <p :if={@state.errors[:title]} id="new-topic-title-error" class="text-sm text-error">
            {@state.errors[:title]}
          </p>
          <div class="mt-3">
            <span id="new-topic-category-label" class="label mb-1">{gettext("Category")}</span>
            <.dropdown
              id="new-topic-category"
              name="new_topic[category_id]"
              options={Enum.map(@state.categories, &{&1.name, &1.id})}
              value={@state.category.id}
              labelled_by="new-topic-category-label"
            />
          </div>
          <p :if={@state.topical?} id="new-topic-topical" class="mt-3 text-sm">
            {gettext("Topics in this category have an icon, chosen on the New topic page.")}
            <.link href={~p"/c/#{@state.category.slug}/new"} class="link">
              {gettext("Go to New topic")}
            </.link>
          </p>
          <div :if={!@state.topical?}>
            <label class="block mt-3">
              <span class="label mb-1">{gettext("First message")}</span>
              <textarea
                name="new_topic[body]"
                id="new-topic-body"
                rows="4"
                required
                class="textarea w-full"
              >{@state.params["body"]}</textarea>
            </label>
            <p :if={@state.errors[:body]} id="new-topic-body-error" class="text-sm text-error">
              {@state.errors[:body]}
            </p>
            <fieldset :if={@state.tags != []} id="new-topic-tags" class="mt-3">
              <legend class="label mb-1">{gettext("Tags (choose at least one)")}</legend>
              <input type="hidden" name="new_topic[tag_ids][]" value="" />
              <div class="tag-choices">
                <label :for={tag <- @state.tags} class="tag-choice">
                  <input
                    type="checkbox"
                    name="new_topic[tag_ids][]"
                    value={tag.id}
                    checked={tag.id in List.wrap(@state.params["tag_ids"])}
                    class="checkbox checkbox-xs"
                  />
                  {tag.name}
                </label>
              </div>
              <p
                :if={@state.errors[:tag_ids]}
                id="new-topic-tags-error"
                class="text-sm text-error"
              >
                {@state.errors[:tag_ids]}
              </p>
            </fieldset>
            <details :if={@state.permissions?} id="new-topic-permissions" class="mt-3">
              <summary class="label cursor-pointer">{gettext("Topic permissions")}</summary>
              <p class="text-sm opacity-70 mt-1">
                {gettext("Over what the category gives; owners and administrators may do everything.")}
              </p>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th scope="col">{gettext("Role")}</th>
                      <th :for={right <- Access.topic_rights()} scope="col">
                        {IdejoWeb.TopicPermissionsHTML.right_label(right)}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={role <- @state.roles}>
                      <th scope="row">{role.name}</th>
                      <td :for={right <- Access.topic_rights()}>
                        <.dropdown
                          id={"new-topic-permission-#{role.id}-#{right}"}
                          name={"permissions[#{role.id}][#{right}]"}
                          options={
                            IdejoWeb.TopicPermissionsHTML.choices(
                              Map.fetch!(@state.inherited, {role.id, right})
                            )
                          }
                          value={chosen(@state, role.id, right)}
                          label={IdejoWeb.TopicPermissionsHTML.cell_label(right, role)}
                        />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </details>
          </div>
          <p
            :if={@state.errors[:base]}
            id="new-topic-error"
            role="alert"
            class="text-sm text-error mt-2"
          >
            {@state.errors[:base]}
          </p>
          <div class="modal-action">
            <button :if={!@state.topical?} class="btn btn-sm btn-primary">
              {gettext("Start topic")}
            </button>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_new_topic">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end
end
