# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Router do
  use IdejoWeb, :router

  import IdejoWeb.UserAuth

  # The policy is set by IdejoWeb.Plugs.ContentSecurityPolicy below, with
  # per-request nonces, so Sobelow cannot see it (SP-05).
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IdejoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug IdejoWeb.Plugs.ContentSecurityPolicy
    plug IdejoWeb.Plugs.RequireSetup
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", IdejoWeb do
    pipe_through :browser

    get "/", PageController, :home

    # First-run wizard (AD-01), only while the server has no owner.
    get "/setup", SetupController, :new
    post "/setup", SetupController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", IdejoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:idejo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      # Composer prototype, ahead of M3 (in-memory, see Idejo.Messages.DemoTopic).
      live "/topic", IdejoWeb.DemoTopicLive

      live_dashboard "/dashboard",
        metrics: IdejoWeb.Telemetry,
        csp_nonce_assign_key: %{script: :script_csp_nonce, style: :style_csp_nonce}

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :script_csp_nonce, style: :style_csp_nonce}
    end
  end

  ## Accounts (AC-01). Public forms are plain controllers so they work without JavaScript.

  scope "/users", IdejoWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/sign-up", UserRegistrationController, :new
    post "/sign-up", UserRegistrationController, :create
    get "/sign-in", UserSessionController, :new
    post "/sign-in", UserSessionController, :create

    # Password reset by email (AC-02).
    get "/reset-password", UserResetPasswordController, :new
    post "/reset-password", UserResetPasswordController, :create
    get "/reset-password/:token", UserResetPasswordController, :edit
    put "/reset-password/:token", UserResetPasswordController, :update
  end

  scope "/users", IdejoWeb do
    pipe_through [:browser, :require_authenticated_user]

    post "/confirm", UserConfirmationController, :create
  end

  ## Admin panel (AD-02), signed-in LiveViews for owners and administrators only.

  scope "/admin", IdejoWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_administrator]

    live_session :admin, on_mount: [{IdejoWeb.UserAuth, :require_administrator}] do
      live "/", SettingsLive
      live "/email", EmailLive
      live "/users", UsersLive
      live "/invites", InvitesLive
      live "/roles", RolesLive
      live "/users/:id", UserLive
      live "/categories", CategoriesLive
      live "/permissions", PermissionsLive
      live "/permissions/:slug", PermissionsLive
    end
  end

  scope "/users", IdejoWeb do
    pipe_through [:browser]

    delete "/sign-out", UserSessionController, :delete
    get "/confirm/:token", UserConfirmationController, :edit
    post "/confirm/:token", UserConfirmationController, :update
  end
end
