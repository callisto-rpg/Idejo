# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AD14HeadlessSetupTest do
  @moduledoc """
  AD-14: `bin/idejo-admin setup --name NAME --owner-email EMAIL [--registration
  open|invite|closed]`, an alternative to the first-run wizard through the same code. The
  owner is created as an invite and chooses a password from a link; a second run refuses.
  With it, the closed registration mode (steward decision, 2026-11-02): nobody signs up.
  """
  # Writes the settings rows every test shares, and switches the mailer in one test.
  use IdejoWeb.ConnCase, async: false

  import ExUnit.CaptureIO
  import Idejo.AccountsFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Release
  alias Idejo.Repo
  alias Idejo.Settings
  alias Idejo.Setup

  defp setup!(opts) do
    capture_io(fn -> assert Release.setup(opts) == :ok end)
  end

  # Release.setup/1 fails as under the command line: a message, then exit({:shutdown, 1}).
  defp refused(opts) do
    capture_io(fn -> assert catch_exit(Release.setup(opts)) == {:shutdown, 1} end)
  end

  defp owner_by_email(email), do: Repo.get_by!(User, email: email)

  # What a setup leaves behind, the parts both ways must agree on.
  defp state(owner) do
    owner = Repo.reload!(owner)

    %{
      setup_needed?: Setup.needed?(),
      roles: owner |> Access.roles_of() |> Enum.map(& &1.name) |> Enum.sort(),
      confirmed?: owner.confirmed_at != nil,
      welcomed?: owner.welcomed_at != nil,
      status: owner.status,
      server_name: Settings.get(:server_name),
      registration_mode: Settings.get(:registration_mode),
      audit:
        Audit.list_entries()
        |> Enum.map(&{&1.change, Map.drop(&1.after, ["user"])})
        |> Enum.sort(),
      activities:
        Repo.aggregate(
          from(a in Idejo.Federation.Activity, where: a.object_uri == ^owner.uri),
          :count
        )
    }
  end

  @tag req: "AD-14"
  test "AD-14 headless setup leaves the same state as the wizard" do
    # The wizard, inside a transaction rolled back once its state is read.
    {:error, wizard} =
      Repo.transaction(fn ->
        {:ok, owner} =
          Setup.complete(
            Setup.token(),
            %{
              "email" => "olga@idejo.test",
              "username" => "olga",
              "display_name" => "olga",
              "password" => "a long enough password"
            },
            %{"server_name" => "Garden Club"}
          )

        Repo.rollback(state(owner))
      end)

    assert Setup.needed?()
    output = setup!(name: "Garden Club", owner_email: "olga@idejo.test")
    owner = owner_by_email("olga@idejo.test")

    assert state(owner) == wizard
    assert wizard.roles == ["member", "owner"] and not wizard.setup_needed?

    # The wizard's entries name the owner who filled it in; the command line's nobody.
    assert Enum.all?(Audit.list_entries(), &is_nil(&1.admin_id))
    assert owner.username == "olga"
    assert output =~ "Garden Club is set up. Its owner is olga@idejo.test (username olga)."
    assert output =~ "An email with a link to choose a password went to olga@idejo.test"
  end

  @tag req: "AD-14"
  test "AD-14 the owner has no password until they follow the emailed link" do
    output =
      setup!(name: "Garden Club", owner_email: "Olga.Owner@idejo.test", registration: "invite")

    owner = owner_by_email("Olga.Owner@idejo.test")
    assert {owner.username, owner.display_name} == {"Olga_Owner", "Olga.Owner"}
    assert Settings.get(:registration_mode) == "invite_only"

    # Nothing on the command line or in its output signs in.
    refute output =~ "/users/reset-password/"
    refute Accounts.get_user_by_email_and_password(owner.email, "")
    refute Accounts.get_user_by_email_and_password(owner.email, "Garden Club")

    assert_email_sent(fn email ->
      assert email.to == [{"", "Olga.Owner@idejo.test"}]
      assert email.subject == "You are the owner of Garden Club"
      assert email.text_body =~ "within 7 days"
      [_, token] = Regex.run(~r{/users/reset-password/([\w-]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    assert_received {:token, token}

    # The password reset page takes the link, once.
    conn = get(build_conn(), ~p"/users/reset-password/#{token}")
    assert html_response(conn, 200) =~ "Choose a new password"

    conn =
      put(build_conn(), ~p"/users/reset-password/#{token}", %{
        "user" => %{
          "password" => "my chosen password",
          "password_confirmation" => "my chosen password"
        }
      })

    assert redirected_to(conn) == ~p"/users/sign-in"
    assert %User{} = Accounts.get_user_by_email_and_password(owner.email, "my chosen password")
    refute Accounts.get_user_by_reset_password_token(token)
  end

  @tag req: "AD-14"
  test "AD-14 without email, the link is printed for the operator" do
    previous = Application.get_env(:idejo, Idejo.Mailer)
    Application.put_env(:idejo, Idejo.Mailer, adapter: Swoosh.Adapters.SMTP)
    on_exit(fn -> Application.put_env(:idejo, Idejo.Mailer, previous) end)

    output = setup!(name: "Garden Club", owner_email: "olga@idejo.test")

    assert output =~
             "could not be sent (no SMTP server is set: Admin → Email, or IDEJO_SMTP_HOST)"

    assert output =~ "it works once, for 7 days"
    base = Application.fetch_env!(:idejo, :base_uri)
    [_, token] = Regex.run(~r{#{base}/users/reset-password/([\w-]+)}, output)
    assert Accounts.get_user_by_reset_password_token(token).email == "olga@idejo.test"
    refute Setup.needed?()
  end

  @tag req: "AD-14"
  test "AD-14 a second run refuses and changes nothing" do
    setup!(name: "Garden Club", owner_email: "olga@idejo.test", registration: "closed")
    before = {Repo.aggregate(User, :count), Audit.list_entries(), Settings.all()}

    output = refused(name: "Other Club", owner_email: "otto@idejo.test", registration: "open")
    assert output =~ "idejo is already set up: nothing changed."
    assert {Repo.aggregate(User, :count), Audit.list_entries(), Settings.all()} == before

    # The wizard refuses too.
    assert Setup.complete(Setup.token(), %{}, %{"server_name" => "x"}) ==
             {:error, :already_set_up}
  end

  @tag req: "AD-14"
  test "AD-14 each bad argument is refused, changing nothing" do
    for {opts, message} <- [
          {[name: "  ", owner_email: "olga@idejo.test"], "The server name (--name) is empty."},
          {[name: "Club", owner_email: ""], "The owner's email (--owner-email) is empty."},
          {[name: "Club", owner_email: "olga"], "the owner's email must have the @ sign"},
          {[name: "Club", owner_email: "olga@idejo.test", registration: "sometimes"],
           "--registration must be open, invite or closed."},
          {[name: String.duplicate("x", 81), owner_email: "olga@idejo.test"],
           "the server name should be at most 80 character(s)"}
        ] do
      assert refused(opts) =~ message
    end

    assert Setup.needed?()
    # Only the server account automessages are sent by (made by a migration).
    refute Repo.exists?(from u in User, where: u.status != "system")
    assert Audit.list_entries() == []
  end

  @tag :tmp_dir
  @tag req: "AD-14"
  test "AD-14 the idejo-admin script checks its arguments and quotes them", %{tmp_dir: dir} do
    script = Path.join(dir, "idejo-admin")
    File.cp!("rel/overlays/bin/idejo-admin", script)

    # A stand-in for the release's bin/idejo: no server running, and eval records its code.
    File.write!(Path.join(dir, "idejo"), """
    #!/bin/sh
    case $1 in
      pid) exit 1 ;;
      eval) printf '%s' "$2" > "$(dirname "$0")/evaluated" ;;
    esac
    """)

    File.chmod!(Path.join(dir, "idejo"), 0o755)
    run = &System.cmd("sh", [script | &1], stderr_to_stdout: true)

    assert {_, 0} =
             run.([
               "setup",
               "--name",
               ~s(The "Garden" #{1 + 1} \\ Club),
               "--owner-email",
               "olga@idejo.test",
               "--registration",
               "invite"
             ])

    # The values reach Elixir as plain strings, whatever they hold.
    code = File.read!(Path.join(dir, "evaluated"))
    {:ok, {{:., _, [_release, :setup]}, _, [args]}} = Code.string_to_quoted(code)

    assert args == [
             name: ~s(The "Garden" #{1 + 1} \\ Club),
             owner_email: "olga@idejo.test",
             registration: "invite"
           ]

    # Without --registration, open.
    assert {_, 0} = run.(["setup", "--name", "Club", "--owner-email", "olga@idejo.test"])
    assert File.read!(Path.join(dir, "evaluated")) =~ ~s(registration: "open")

    for args <- [
          ["setup"],
          ["setup", "--owner-email", "olga@idejo.test"],
          ["setup", "--name", " ", "--owner-email", "olga@idejo.test"],
          ["setup", "--name", "Club", "--owner-email", "olga"],
          ["setup", "--name", "Club", "--owner-email", "olga@idejo.test", "--registration", "x"],
          ["setup", "--name", "Club", "--owner-email", "olga@idejo.test", "--yes", "now"],
          ["setup", "--name", "Club", "--owner-email"]
        ] do
      assert {_, 64} = run.(args), inspect(args)
    end

    {usage, 0} = run.(["help"])
    assert usage =~ "setup --name NAME --owner-email EMAIL [--registration open|invite|closed]"
  end

  describe "closed registration" do
    setup do
      admin = user_with_role_fixture(:administrator)
      {:ok, _} = Settings.update_settings(admin, %{"registration_mode" => "closed"})
      %{admin: admin}
    end

    @tag req: "AD-14"
    test "AD-14 closed: nobody signs up, not even with an invite", %{admin: admin} do
      {:ok, invite} = Accounts.create_invite(admin)

      attrs = %{
        "email" => "new@idejo.test",
        "username" => "newcomer",
        "display_name" => "New",
        "password" => "a long enough password",
        "invite_code" => invite.code
      }

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "cannot sign up: sign-ups are closed" in Idejo.DataCase.errors_on(changeset).email
      refute Accounts.get_user_by_email("new@idejo.test")

      # The form is gone, and posting it anyway is refused.
      html = html_response(get(build_conn(), ~p"/users/sign-up"), 200)
      assert html =~ "This server is not taking new members."
      refute html =~ ~s(action="/users/sign-up")

      conn = post(build_conn(), ~p"/users/sign-up", %{"user" => attrs})
      assert html_response(conn, 200) =~ "This server is not taking new members."
      refute Accounts.get_user_by_email("new@idejo.test")
      refute Accounts.sign_ups_open?()
    end

    @tag req: "AD-14"
    test "AD-14 closed: no Sign up link anywhere" do
      for path <- [~p"/", ~p"/users/sign-in"] do
        refute html_response(get(build_conn(), path), 200) =~ ~s(href="/users/sign-up"), path
      end
    end

    @tag req: "AD-14"
    test "AD-14 closed: the admin panel offers it and says invites do not work", %{
      admin: admin
    } do
      conn = log_in_user(build_conn(), admin)
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Nobody (sign-ups closed)"

      {:ok, view, _html} = live(conn, ~p"/admin/invites")
      assert has_element?(view, "#invites-closed")
    end
  end
end
