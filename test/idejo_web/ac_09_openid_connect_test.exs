# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AC09OpenIDConnectTest do
  @moduledoc """
  AC-09: sign-in through one OpenID Connect provider, against a fake provider
  (`Idejo.FakeOIDCProvider`): authorization code with PKCE, `state` and `nonce`; accounts
  linked by issuer and subject, never email; the registration mode applies; the provider
  never grants a role.
  """
  # Starts a provider and changes the OpenID Connect settings, which are global.
  use IdejoWeb.ConnCase, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  import Ecto.Query
  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDC, User, UserIdentity}
  alias Idejo.FakeOIDCProvider
  alias Idejo.Repo
  alias Idejo.Settings

  setup do
    %{provider: FakeOIDCProvider.start!()}
  end

  @ada %{
    "sub" => "ada-123",
    "email" => "ada@idejo.test",
    "email_verified" => true,
    "name" => "Ada Lovelace",
    "preferred_username" => "ada"
  }

  # Goes to the provider and back: the app's redirect, then the callback with a code for
  # `claims`. `opts`: `:state` to send another one, `:key`, `:path` to start from.
  defp through(provider, claims, opts \\ []) do
    conn = get(Keyword.get(opts, :conn, build_conn()), Keyword.get(opts, :path, ~p"/users/oidc"))
    location = redirected_to(conn, 302)
    assert String.starts_with?(location, provider.issuer <> "/authorize?")
    request = FakeOIDCProvider.authorization(location)
    code = FakeOIDCProvider.code(provider, request, claims, Keyword.take(opts, [:key]))
    query = %{"code" => code, "state" => Keyword.get(opts, :state, request["state"])}
    get(conn, ~p"/users/oidc/callback?#{query}")
  end

  defp identities, do: Repo.all(UserIdentity)

  defp signed_in?(conn), do: get_session(conn, :user_token) != nil

  @tag req: "AC-09"
  test "AC-09 a first sign-in makes one member and one link; the next reuses them", %{
    provider: provider
  } do
    conn = through(provider, @ada)
    assert redirected_to(conn) == ~p"/"
    assert signed_in?(conn)

    user = Repo.get_by!(User, email: "ada@idejo.test")
    assert {user.username, user.display_name} == {"ada", "Ada Lovelace"}
    assert Accounts.confirmed?(user)
    assert [%UserIdentity{issuer: issuer, subject: "ada-123"}] = identities()
    assert issuer == provider.issuer

    # Again, even with another email at the provider: linked by subject, not email.
    conn = through(provider, %{@ada | "email" => "ada.new@idejo.test"})
    assert signed_in?(conn)
    assert Repo.aggregate(from(u in User, where: u.status == "active"), :count) == 1
    assert length(identities()) == 1
  end

  @tag req: "AC-09"
  test "AC-09 a wrong or reused state, and a provider error, are refused", %{provider: provider} do
    log =
      capture_log(fn ->
        conn = through(provider, @ada, state: "not-the-state")
        refute signed_in?(conn)
        assert redirected_to(conn) == ~p"/users/sign-in"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not work"

        # The request is used once: the same callback again finds none.
        conn = get(build_conn(), ~p"/users/oidc")
        request = FakeOIDCProvider.authorization(redirected_to(conn, 302))
        code = FakeOIDCProvider.code(provider, request, @ada)
        query = %{"code" => code, "state" => request["state"]}
        first = get(conn, ~p"/users/oidc/callback?#{query}")
        assert signed_in?(first)
        replay = get(conn |> recycle(), ~p"/users/oidc/callback?#{query}")
        refute signed_in?(replay)

        conn = get(build_conn(), ~p"/users/oidc")
        refute signed_in?(get(conn, ~p"/users/oidc/callback?error=access_denied"))
      end)

    refute log =~ FakeOIDCProvider.client_secret()
    assert length(identities()) == 1
  end

  @tag req: "AC-09"
  test "AC-09 a wrong nonce, a bad signature, the wrong audience or an expired token are refused",
       %{provider: provider} do
    now = System.system_time(:second)

    log =
      capture_log(fn ->
        for {claims, opts} <- [
              {Map.put(@ada, "nonce", "another-nonce"), []},
              {@ada, [key: :other]},
              {Map.put(@ada, "aud", "another-client"), []},
              {Map.merge(@ada, %{"iat" => now - 900, "exp" => now - 600}), []},
              {Map.put(@ada, "iss", "https://elsewhere.idejo.test"), []}
            ] do
          conn = through(provider, claims, opts)
          refute signed_in?(conn), inspect({claims, opts})
          assert redirected_to(conn) == ~p"/users/sign-in"
        end
      end)

    assert identities() == []
    refute Repo.get_by(User, email: "ada@idejo.test")
    refute log =~ FakeOIDCProvider.client_secret()
  end

  @tag req: "AC-09"
  test "AC-09 the registration mode applies: invite-only needs an invite, closed takes nobody",
       %{provider: provider} do
    admin = user_with_role_fixture(:administrator)
    {:ok, _} = Settings.update_settings(admin, %{"registration_mode" => "invite_only"})

    conn = through(provider, @ada)
    refute signed_in?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Joining is by invitation"
    assert identities() == []

    # The sign-up page's button carries the invite through the provider.
    {:ok, invite} = Accounts.create_invite(admin)
    page = html_response(get(build_conn(), ~p"/users/sign-up?invite=#{invite.code}"), 200)
    assert page =~ "Sign up with Test ID"
    assert page =~ ~s(href="/users/oidc?invite=#{invite.code}")

    conn = through(provider, @ada, path: ~p"/users/oidc?invite=#{invite.code}")
    assert signed_in?(conn)
    user = Repo.get_by!(User, email: "ada@idejo.test")
    assert Repo.reload!(invite).used_by == user.id

    {:ok, _} = Settings.update_settings(admin, %{"registration_mode" => "closed"})
    conn = through(provider, %{@ada | "sub" => "bea-1", "email" => "bea@idejo.test"})
    refute signed_in?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not taking new members"
    refute Repo.get_by(User, email: "bea@idejo.test")
  end

  @tag req: "AC-09"
  test "AC-09 the provider never grants a role", %{provider: provider} do
    claims =
      Map.merge(@ada, %{
        "roles" => ["owner", "administrator"],
        "groups" => ["administrator", "moderator"],
        "role" => "administrator"
      })

    assert signed_in?(through(provider, claims))
    user = Repo.get_by!(User, email: "ada@idejo.test")
    assert user |> Access.roles_of() |> Enum.map(& &1.name) == ["member"]
    refute Access.administrator?(user)
  end

  @tag req: "AC-09"
  test "AC-09 a banned member stays banned", %{provider: provider} do
    assert signed_in?(through(provider, @ada))
    user = Repo.get_by!(User, email: "ada@idejo.test")
    {:ok, _} = Accounts.ban_user(user_with_role_fixture(:administrator), user, nil, "spam")

    conn = through(provider, @ada)
    refute signed_in?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "This account is banned."
  end

  @tag req: "AC-09"
  test "AC-09 an account with the same email is never linked by itself; its owner links it",
       %{provider: provider} do
    local = user_fixture(%{email: "ada@idejo.test"})

    conn = through(provider, @ada)
    refute signed_in?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already uses the email address"
    assert identities() == []

    # Signed in with the password, the member links Test ID from the profile.
    signed_in = log_in_user(build_conn(), local)
    {:ok, view, _html} = live(signed_in, ~p"/users/settings")
    assert has_element?(view, ~s(#oidc-link[href="/users/oidc?intent=link"]))

    conn = through(provider, @ada, conn: signed_in, path: ~p"/users/oidc?intent=link")
    assert redirected_to(conn) == ~p"/users/settings"
    assert [%UserIdentity{user_id: user_id}] = identities()
    assert user_id == local.id

    # From then on, Test ID signs them in; another account cannot take the same person.
    assert get_session(through(provider, @ada), :user_token)
    other = log_in_user(build_conn(), user_fixture())
    conn = through(provider, @ada, conn: other, path: ~p"/users/oidc?intent=link")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already linked to another account"
    assert length(identities()) == 1
  end

  @tag req: "AC-09"
  test "AC-09 an email the provider has not verified is verified here", %{provider: provider} do
    conn = through(provider, %{@ada | "email_verified" => false})
    assert signed_in?(conn)
    user = Repo.get_by!(User, email: "ada@idejo.test")
    refute Accounts.confirmed?(user)
    assert_email_sent(subject: "Verify your email address")

    # No email at all: no account.
    conn = through(provider, Map.drop(%{@ada | "sub" => "x-2"}, ["email"]))
    refute signed_in?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not give an email address"
  end

  @tag req: "AC-09"
  test "AC-09 with local accounts off, passwords sign in only owners and administrators",
       %{provider: provider} do
    Application.put_env(:idejo, :local_accounts, false)
    member = user_fixture()
    owner = user_with_role_fixture(:owner)

    page = html_response(get(build_conn(), ~p"/users/sign-in"), 200)
    assert page =~ "Sign in with Test ID"
    refute page =~ ~s(id="sign_in_form")
    refute page =~ "Forgot your password?"
    assert page =~ ~s(href="/users/sign-in?with=password")

    page = html_response(get(build_conn(), ~p"/users/sign-in?with=password"), 200)
    assert page =~ ~s(id="sign_in_form")

    password = fn user ->
      post(build_conn(), ~p"/users/sign-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })
    end

    refute signed_in?(password.(member))
    assert signed_in?(password.(owner))

    # The command line's owner reset still lets the owner in (AD-09).
    output = capture_io(fn -> Idejo.Release.reset_owner_password(owner.username) end)
    [_, new_password] = Regex.run(~r/\n\n    (\S+)\n/, output)

    conn =
      post(build_conn(), ~p"/users/sign-in", %{
        "user" => %{"email" => owner.email, "password" => new_password}
      })

    assert signed_in?(conn)

    # No sign-up form, no reset by email; the provider still makes members.
    page = html_response(get(build_conn(), ~p"/users/sign-up"), 200)
    assert page =~ "Sign up with Test ID"
    refute page =~ ~s(action="/users/sign-up")

    attrs = %{
      "email" => "new@idejo.test",
      "username" => "newcomer",
      "display_name" => "New",
      "password" => "a long enough password"
    }

    post(build_conn(), ~p"/users/sign-up", %{"user" => attrs})
    refute Accounts.get_user_by_email("new@idejo.test")
    assert redirected_to(get(build_conn(), ~p"/users/reset-password")) == ~p"/users/sign-in"
    assert signed_in?(through(provider, @ada))

    # The profile has no password to change for a member.
    {:ok, view, _html} = live(log_in_user(build_conn(), member), ~p"/users/settings")
    refute has_element?(view, "#password-form")
    refute has_element?(view, "#delete-account-form")
  end

  @tag req: "AC-09"
  test "AC-09 a member without a password deletes their account after signing in again",
       %{provider: provider} do
    conn = through(provider, @ada)
    user = Repo.get_by!(User, email: "ada@idejo.test")

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, ~s(#delete-reauth[href="/users/oidc?intent=reauth"]))
    refute has_element?(view, "#delete-account-oidc")

    # The provider is asked to sign them in again.
    asked = get(conn, ~p"/users/oidc?intent=reauth")
    request = FakeOIDCProvider.authorization(redirected_to(asked, 302))
    assert {request["prompt"], request["max_age"]} == {"login", "0"}

    conn = through(provider, @ada, conn: conn, path: ~p"/users/oidc?intent=reauth")
    assert redirected_to(conn) == ~p"/users/settings#delete-heading"

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    view |> element("#delete-account-oidc") |> render_click()

    user = Repo.reload!(user)
    assert user.status == "deleted"
    assert identities() == []

    # A confirmation older than five minutes does not do.
    other = user_fixture()
    {:ok, _} = OIDC.link(other, %{"iss" => provider.issuer, "sub" => "o-1"})
    stale = System.system_time(:second) - 301
    assert Accounts.delete_user(other, {:oidc, stale}) == {:error, :reauthentication}

    assert Accounts.delete_user(user_fixture(), {:oidc, System.system_time(:second)}) ==
             {:error, :reauthentication}
  end

  @tag req: "AC-09"
  test "AC-09 a partial configuration stops the boot, and so do local accounts off alone" do
    read = fn env ->
      names =
        ~w(IDEJO_OIDC_ISSUER IDEJO_OIDC_CLIENT_ID IDEJO_OIDC_CLIENT_SECRET IDEJO_OIDC_LABEL IDEJO_LOCAL_ACCOUNTS)

      saved = Map.new(names, &{&1, System.get_env(&1)})

      try do
        Enum.each(names, &System.delete_env/1)
        Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
        Config.Reader.read!("config/runtime.exs", env: :test)[:idejo]
      after
        for {name, value} <- saved,
            do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
      end
    end

    full = %{
      "IDEJO_OIDC_ISSUER" => "https://id.idejo.test",
      "IDEJO_OIDC_CLIENT_ID" => "forum-a",
      "IDEJO_OIDC_CLIENT_SECRET" => "s3cret",
      "IDEJO_OIDC_LABEL" => "Idejo ID"
    }

    assert read.(full)[:oidc] == [
             issuer: "https://id.idejo.test",
             client_id: "forum-a",
             client_secret: "s3cret",
             label: "Idejo ID"
           ]

    assert read.(Map.put(full, "IDEJO_LOCAL_ACCOUNTS", "off"))[:local_accounts] == false
    assert read.(%{})[:local_accounts] == true
    refute read.(%{})[:oidc]

    for name <- Map.keys(full) do
      assert_raise RuntimeError, ~r/only partly set up: #{name} missing/, fn ->
        read.(Map.delete(full, name))
      end
    end

    assert_raise RuntimeError, ~r/IDEJO_LOCAL_ACCOUNTS=off needs OpenID Connect/, fn ->
      read.(%{"IDEJO_LOCAL_ACCOUNTS" => "off"})
    end

    assert_raise RuntimeError, ~r/must be on or off/, fn ->
      read.(%{"IDEJO_LOCAL_ACCOUNTS" => "maybe"})
    end
  end

  @tag req: "AC-09"
  test "AC-09 no tokens are kept, and nothing is offered while it is not set up" do
    assert UserIdentity.__schema__(:fields) == [:id, :user_id, :issuer, :subject, :inserted_at]

    Application.delete_env(:idejo, :oidc)
    assert get(build_conn(), ~p"/users/oidc").status == 404
    refute html_response(get(build_conn(), ~p"/users/sign-in"), 200) =~ "Sign in with"
  end

  @tag req: "AC-09"
  test "AC-09 the pages with the provider's button pass the accessibility audit" do
    for path <- [~p"/users/sign-in", ~p"/users/sign-up", ~p"/users/sign-in?with=password"] do
      problems = IdejoWeb.Accessibility.audit(html_response(get(build_conn(), path), 200))
      assert problems == [], "#{path}: " <> Enum.join(problems, "\n")
    end

    {:ok, _view, html} = live(log_in_user(build_conn(), user_fixture()), ~p"/users/settings")
    assert html =~ "Link Test ID"
    problems = IdejoWeb.Accessibility.audit(html, page: false)
    assert problems == [], Enum.join(problems, "\n")
  end
end
