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

  # SE-04: for search engines; no session, nothing personal.
  scope "/", IdejoWeb do
    get "/sitemap.xml", SitemapController, :sitemap
    get "/robots.txt", SitemapController, :robots
    # TP-12: uploaded images, public, no session.
    get "/uploads/:name", UploadController, :show
  end

  scope "/", IdejoWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Public pages (AC-05): server-rendered, no JavaScript needed.
    get "/c/:slug", CategoryController, :show
    get "/t/:id", TopicController, :show
    get "/t/:id/:slug", TopicController, :show
    get "/m/:id", MessageController, :show
    # SE-01: the Search screen (MVP §5), public.
    get "/search", SearchController, :index
    # TP-19: "Filter by tag", public.
    get "/tags", TagController, :index
    # A user's URI (FD-01): the card an @mention leads to (TP-10).
    get "/u/:id", UserController, :show
    # TP-10: a role's page, which a +role mention links to.
    get "/r/:slug", RoleController, :show

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

    # Profile and account (AC-04), for the signed-in user.
    live_session :signed_in, on_mount: [{IdejoWeb.UserAuth, :require_authenticated}] do
      live "/settings", UserSettingsLive
    end
  end

  ## Topics (TP-01): starting one needs a signed-in user with the start right.

  scope "/", IdejoWeb do
    pipe_through [:browser, :require_authenticated_user]

    # TP-07: topics with something new across categories, no JavaScript needed.
    get "/unread", UnreadController, :index
    # NO-01: the Notifications screen (MVP §5).
    get "/notifications", NotificationController, :index
    post "/notifications/read", NotificationController, :read_all
    get "/notifications/:id", NotificationController, :show
    # MO-01, MO-03: the report queue and the moderation log, for moderators.
    get "/moderation", ModerationController, :index
    post "/moderation/reports/:message_id", ModerationController, :handle_reports
    get "/moderation/log", ModerationController, :log
    # MO-02: server moderators ban an account or lift a ban.
    post "/u/:id/ban", BanController, :create
    delete "/u/:id/ban", BanController, :delete
    # MO-01: report a message.
    get "/m/:id/report", ReportController, :new
    post "/m/:id/report", ReportController, :create
    # TP-13: follow or unfollow a topic, plain forms that work without JavaScript.
    # TP-14: moderators lock, unlock, pin or unpin a topic (a plain form).
    post "/t/:id/moderate", TopicModerationController, :create
    # TP-19: change a topic's tags (the :tag right), a plain form.
    post "/t/:id/tags", TopicTagsController, :update
    post "/t/:id/follow", FollowController, :create
    delete "/t/:id/follow", FollowController, :delete

    live_session :member, on_mount: [{IdejoWeb.UserAuth, :require_authenticated}] do
      live "/c/:slug/new", NewTopicLive
      # TP-09: "New topic from this" message.
      live "/m/:id/new-topic", NewTopicLive, :fork
    end
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
      live "/tags", TagsLive
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
