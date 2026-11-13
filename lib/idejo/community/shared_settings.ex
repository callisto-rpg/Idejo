# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Community.SharedSettings do
  @moduledoc """
  One member's Profile and account settings, saved on every forum of the group at once
  (steward request, 2026-11-13). Optional and generic, like the chat service
  (`Idejo.Community.Chat`): only between installs sharing one sign-in.

  The group's inbox (`Idejo.Inbox`) offers "Save for all forums" beside each section's Save:
  `export/2` writes the member's sections as JSON, and `Idejo.Inbox.save_everywhere/2` sends
  them to the group's service, which hands them to each forum the member joined with a
  ticket of scope `settings`. The forum checks the ticket (`Chat.check_ticket/2`) and
  `save/2` saves each section through the same functions as its own page.

  Sections: `profile` (display name, user tag; never the username), `bio`, `avatar` (both
  pictures as WebP in Base64, or `null` for none), `writing`, `controls`, `private`,
  `email` and `push`. Ignored users, apps and devices, push devices, the password and
  deleting the account stay each forum's own.

  `notifications_shared` (users column): on the inbox, the member's choice to use one set of
  email and push choices everywhere ("Use these notification choices on all my forums");
  each later save of those sections goes to every forum. On a forum, it marks those choices
  as the inbox's: its page shows them read-only, with a link there, and refuses to change
  them (`locked?/2`), so a forum never drifts from the shared choices. Turning it off on
  the inbox turns it off everywhere and each forum keeps the choices it had.
  """

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Notifications.Digest
  alias Idejo.{Push, Uploads}

  @sections ~w(profile bio avatar writing controls private email push)

  # Base64 of a 256 px WebP is far below this; anything larger is refused unread.
  @max_picture 2_000_000

  @fields %{
    "profile" => ~w(display_name user_tag),
    "bio" => ~w(bio_md),
    "writing" => ~w(auto_punctuation graphical_composer),
    "controls" => ~w(controls_on_mobile controls_on_desktop),
    "private" => ~w(accepts_private_messages),
    "email" =>
      ~w(mentions role_mentions own_topics followed_topics new_topics all_activity once_a_week),
    "push" => ~w(reply mention role_mention followed private)
  }

  @doc "The sections a member can save for all forums."
  @spec sections() :: [String.t()]
  def sections, do: @sections

  @doc """
  Whether `section` (`"email"` or `"push"`) is the inbox's on this forum, so not changed
  here.
  """
  @spec locked?(User.t(), String.t()) :: boolean()
  def locked?(%User{notifications_shared: true}, section) when section in ~w(email push),
    do: not Idejo.Inbox.on?()

  def locked?(_user, _section), do: false

  ## The inbox's side

  @doc """
  `user`'s `sections` as the forums take them, plus `notifications_shared` when asked
  (`shared:`, true or false).
  """
  @spec export(User.t(), [String.t()], keyword()) :: map()
  def export(%User{} = user, sections, opts \\ []) do
    map =
      for section <- sections, section in @sections, into: %{} do
        {section, export_section(user, section)}
      end

    case Keyword.fetch(opts, :shared) do
      {:ok, shared} when is_boolean(shared) -> Map.put(map, "notifications_shared", shared)
      :error -> map
    end
  end

  defp export_section(user, "email"), do: pick(Digest.preferences(user), "email")
  defp export_section(user, "push"), do: pick(Push.preferences(user), "push")

  defp export_section(user, "avatar"),
    do: %{"light" => picture(user.avatar_id), "dark" => picture(user.avatar_dark_id)}

  defp export_section(user, section), do: pick(user, section)

  defp pick(struct, section),
    do: Map.new(@fields[section], &{&1, Map.fetch!(struct, String.to_existing_atom(&1))})

  defp picture(nil), do: nil

  defp picture(id) do
    with {_upload, file} <- Uploads.get_by_name("#{id}.webp"),
         {:ok, bytes} <- File.read(file) do
      Base.encode64(bytes)
    else
      _ -> nil
    end
  end

  ## A forum's side

  @doc """
  Saves on this forum what the inbox sent for `user`: `%{saved: [section], failed:
  [section]}`. Unknown keys are ignored; a section that does not save leaves the others.
  """
  @spec save(User.t(), map()) :: %{saved: [String.t()], failed: [String.t()]}
  def save(%User{} = user, settings) when is_map(settings) do
    {user, results} =
      Enum.reduce(@sections, {user, []}, fn section, acc ->
        save_section(acc, section, Map.get(settings, section))
      end)

    results = Enum.reverse(save_shared(results, user, settings["notifications_shared"]))

    %{
      saved: for({section, :ok} <- results, do: section),
      failed: for({section, :error} <- results, do: section)
    }
  end

  defp save_section({user, results}, section, value) when is_map(value) do
    case apply_section(user, section, value) do
      {:ok, user} -> {user, [{section, :ok} | results]}
      _ -> {user, [{section, :error} | results]}
    end
  end

  defp save_section(acc, _section, _value), do: acc

  defp save_shared(results, user, shared) when is_boolean(shared) do
    case Accounts.set_notifications_shared(user, shared) do
      {:ok, _} -> [{"notifications_shared", :ok} | results]
      _ -> [{"notifications_shared", :error} | results]
    end
  end

  defp save_shared(results, _user, _shared), do: results

  defp apply_section(user, "profile", value),
    do: Accounts.update_user_profile(user, only(value, "profile"))

  defp apply_section(user, "bio", value), do: Accounts.update_user_bio(user, only(value, "bio"))

  defp apply_section(user, "writing", value),
    do: Accounts.update_user_writing(user, only(value, "writing"))

  defp apply_section(user, "controls", value),
    do: Accounts.update_user_controls(user, only(value, "controls"))

  defp apply_section(user, "private", value),
    do: Accounts.update_user_private_messages(user, only(value, "private"))

  defp apply_section(user, "email", value) do
    with {:ok, _} <- Digest.update_preferences(user, only(value, "email")), do: {:ok, user}
  end

  defp apply_section(user, "push", value) do
    with {:ok, _} <- Push.update_preferences(user, only(value, "push")), do: {:ok, user}
  end

  defp apply_section(user, "avatar", value) do
    with {:ok, user} <- set_picture(user, :light, Map.fetch(value, "light")),
         do: set_picture(user, :dark, Map.fetch(value, "dark"))
  end

  defp only(value, section), do: Map.take(value, @fields[section])

  # Absent: unchanged; null: removed; Base64: stored as a picture chosen here would be.
  defp set_picture(user, _theme, :error), do: {:ok, user}

  defp set_picture(user, theme, {:ok, nil}), do: Accounts.remove_avatar(user, theme)

  defp set_picture(user, theme, {:ok, base64})
       when is_binary(base64) and byte_size(base64) <= @max_picture do
    with {:ok, bytes} <- Base.decode64(base64) do
      path =
        Path.join(System.tmp_dir!(), "idejo-shared-avatar-#{System.unique_integer([:positive])}")

      try do
        File.write!(path, bytes)
        Accounts.set_avatar(user, path, theme)
      after
        File.rm(path)
      end
    end
  end

  defp set_picture(_user, _theme, _value), do: {:error, :invalid}
end
