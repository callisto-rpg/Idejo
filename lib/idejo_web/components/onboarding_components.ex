# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OnboardingComponents do
  @moduledoc """
  The onboarding tour (steward request, 2026-11-22; `Idejo.Onboarding`): a new member's
  first steps, from the sidebar to their first message in the onboarding topic.

  Each step is a hidden `#onboarding-tour` holding its card's text, with what it points at
  (`data-target`, a selector) and where the card goes (`data-place`: `right` of it, or
  `above` it). `assets/js/onboarding_tour.js` draws it: the page under the background
  colour at 50% opacity but for the target, which a glowing outline marks; the card beside
  it with an arrow pointing at it; and every click elsewhere stopped (the target's own
  controls, such as the sidebar topic's ×, too). Without JavaScript nothing shows and
  nothing is stopped.

    1. On any page but the onboarding topic's (`Layouts.app/1`): its link in the sidebar,
       "Open a topic to get started."
    2. On its page (`IdejoWeb.TopicLive`), before the member's first message there: the
       composer, "Type “Hi, I'm {name}” then press Enter".
    3. Once it is sent, while it is open: the composer, "Your message was sent. …
       {onboarding.string.1} and type Ctrl+Enter."
    4. Once it closed: the top of the sidebar, "Congratulations, …", with **Close**. The
       tour is finished then (`Idejo.Accounts.mark_onboarded/1`).
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  attr :step, :integer, required: true, values: [1, 2, 3, 4]
  attr :topic, :map, required: true, doc: "the onboarding topic"
  attr :user, :map, default: nil, doc: "the member (step 2 says their name)"

  def tour(assigns) do
    {target, place} = aim(assigns.step, assigns.topic)
    assigns = assign(assigns, target: target, place: place)

    ~H"""
    <div
      id="onboarding-tour"
      class="onboarding-tour"
      hidden
      data-step={@step}
      data-target={@target}
      data-place={@place}
    >
      <p :if={@step == 1}>{gettext("Open a topic to get started.")}</p>
      <p :if={@step == 2}>
        {gettext("Type “Hi, I'm %{name}” then press", name: @user.display_name)}
        <kbd class="kbd kbd-sm">Enter</kbd>
      </p>
      <p :if={@step == 3}>
        {gettext("Your message was sent. Everyone can see it, but you can still append it.")}
        {Idejo.Onboarding.string(1)} {gettext("and type")}
        <kbd class="kbd kbd-sm">Ctrl</kbd>+<kbd class="kbd kbd-sm">Enter</kbd>.
      </p>
      <p :if={@step == 4}>
        {gettext(
          "Congratulations, you have finished your first message! You can always edit your own messages. You can now return to the forum's homepage by clicking “All” or continue the conversation in #%{title}.",
          title: @topic.title
        )}
      </p>
      <button :if={@step == 4} type="button" class="btn btn-primary btn-sm" data-tour-close>
        {gettext("Close")}
      </button>
    </div>
    """
  end

  defp aim(1, topic),
    do: {~s(#sidebar .sidebar-topic[data-topic-id="#{topic.id}"] .sidebar-topic-link), "right"}

  defp aim(step, _topic) when step in [2, 3], do: {"#composer", "above"}
  defp aim(4, _topic), do: {"#sidebar .sidebar-all", "right"}
end
