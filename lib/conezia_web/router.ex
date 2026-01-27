defmodule ConeziaWeb.Router do
  use ConeziaWeb, :router

  import ConeziaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConeziaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug ConeziaWeb.Plugs.RequestId
    plug ConeziaWeb.Plugs.SecurityHeaders
  end

  pipeline :authenticated do
    plug Guardian.Plug.Pipeline,
      module: Conezia.Guardian,
      error_handler: ConeziaWeb.AuthErrorHandler

    plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated
    plug Guardian.Plug.LoadResource
  end

  pipeline :rate_limited do
    plug ConeziaWeb.Plugs.RateLimiter, :rate_limit
  end

  pipeline :auth_rate_limited_login do
    plug ConeziaWeb.Plugs.AuthRateLimiter, action: :login
  end

  pipeline :auth_rate_limited_register do
    plug ConeziaWeb.Plugs.AuthRateLimiter, action: :register
  end

  pipeline :auth_rate_limited_forgot_password do
    plug ConeziaWeb.Plugs.AuthRateLimiter, action: :forgot_password
  end

  pipeline :auth_rate_limited_verify do
    plug ConeziaWeb.Plugs.AuthRateLimiter, action: :verify_email
  end

  # Web UI Routes (LiveView)

  # Public routes (redirect if authenticated)
  scope "/", ConeziaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{ConeziaWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/login", AuthLive.LoginLive, :index
      live "/register", AuthLive.RegisterLive, :index
      live "/forgot-password", AuthLive.ForgotPasswordLive, :index
    end

    post "/login", SessionController, :create
  end

  # Authenticated routes
  scope "/", ConeziaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ConeziaWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive.Index, :index
      live "/connections", EntityLive.Index, :index
      live "/connections/new", EntityLive.Index, :new
      live "/connections/:id", EntityLive.Show, :show
      live "/connections/:id/edit", EntityLive.Show, :edit
      live "/reminders", ReminderLive.Index, :index
      live "/reminders/new", ReminderLive.Index, :new
      live "/reminders/:id/edit", ReminderLive.Index, :edit
      live "/gifts", GiftLive.Index, :index
      live "/gifts/new", GiftLive.Index, :new
      live "/gifts/:id/edit", GiftLive.Index, :edit
      live "/settings", SettingsLive.Index, :index
      live "/settings/:tab", SettingsLive.Index, :index
    end
  end

  # Integration OAuth routes (authenticated)
  scope "/integrations", ConeziaWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/:service/authorize", IntegrationOAuthController, :authorize
    get "/:service/callback", IntegrationOAuthController, :callback
  end

  # Logout route
  scope "/", ConeziaWeb do
    pipe_through [:browser]

    delete "/logout", SessionController, :delete
  end

  # OAuth routes (public, no CSRF for callback)
  scope "/auth", ConeziaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/google", OAuthController, :google
    get "/google/callback", OAuthController, :google_callback
  end

  # Public authentication endpoints with strict rate limiting
  scope "/api/v1/auth", ConeziaWeb do
    pipe_through [:api, :rate_limited]

    # Login - strictest limits (5/minute)
    scope "/" do
      pipe_through [:auth_rate_limited_login]
      post "/login", AuthController, :login
    end

    # Registration - moderate limits (10/hour)
    scope "/" do
      pipe_through [:auth_rate_limited_register]
      post "/register", AuthController, :register
    end

    # Password reset - strict limits (3/hour)
    scope "/" do
      pipe_through [:auth_rate_limited_forgot_password]
      post "/forgot-password", AuthController, :forgot_password
      post "/reset-password", AuthController, :reset_password
    end

    # Email verification - moderate limits (5/hour)
    scope "/" do
      pipe_through [:auth_rate_limited_verify]
      post "/verify-email", AuthController, :verify_email
    end

    # Other auth endpoints with standard rate limiting
    post "/google", AuthController, :google_oauth
    post "/refresh", AuthController, :refresh
  end

  # Authenticated auth endpoints
  scope "/api/v1/auth", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    post "/logout", AuthController, :logout
  end

  # User endpoints
  scope "/api/v1/users", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/me", UserController, :show
    put "/me", UserController, :update
    delete "/me", UserController, :delete

    get "/me/preferences", UserController, :get_preferences
    put "/me/preferences", UserController, :update_preferences

    get "/me/notifications", UserController, :get_notifications
    put "/me/notifications", UserController, :update_notifications

    get "/me/onboarding", UserController, :get_onboarding
    put "/me/onboarding", UserController, :update_onboarding
    post "/me/onboarding/complete", UserController, :complete_onboarding

    get "/me/authorized-apps", UserController, :list_authorized_apps
    get "/me/authorized-apps/:app_id", UserController, :get_authorized_app
    put "/me/authorized-apps/:app_id", UserController, :update_authorized_app
    delete "/me/authorized-apps/:app_id", UserController, :revoke_authorized_app
  end

  # Entity endpoints
  scope "/api/v1/entities", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", EntityController, :index
    post "/", EntityController, :create
    get "/duplicates", EntityController, :check_duplicates
    post "/merge", EntityController, :merge

    get "/:id", EntityController, :show
    put "/:id", EntityController, :update
    delete "/:id", EntityController, :delete

    get "/:id/interactions", EntityController, :list_interactions
    get "/:id/history", EntityController, :history
    get "/:id/conversations", EntityController, :list_conversations
    get "/:id/reminders", EntityController, :list_reminders
    get "/:id/attachments", EntityController, :list_attachments
    get "/:id/activity", EntityController, :activity

    get "/:id/identifiers", EntityController, :list_identifiers
    post "/:id/identifiers", EntityController, :create_identifier

    post "/:id/tags", EntityController, :add_tags
    delete "/:id/tags/:tag_id", EntityController, :remove_tag

    put "/:id/health-threshold", EntityController, :set_health_threshold

    post "/:id/archive", EntityController, :archive
    post "/:id/unarchive", EntityController, :unarchive
  end

  # Relationship endpoints
  scope "/api/v1/relationships", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", RelationshipController, :index
    post "/", RelationshipController, :create
    get "/:id", RelationshipController, :show
    put "/:id", RelationshipController, :update
    delete "/:id", RelationshipController, :delete
  end

  # Conversation endpoints
  scope "/api/v1/conversations", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", ConversationController, :index
    get "/:id", ConversationController, :show
    put "/:id", ConversationController, :update
    delete "/:id", ConversationController, :delete
  end

  # Communication endpoints
  scope "/api/v1/communications", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    post "/", CommunicationController, :create
  end

  # Reminder endpoints
  scope "/api/v1/reminders", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", ReminderController, :index
    post "/", ReminderController, :create
    get "/:id", ReminderController, :show
    put "/:id", ReminderController, :update
    delete "/:id", ReminderController, :delete
    post "/:id/snooze", ReminderController, :snooze
    post "/:id/complete", ReminderController, :complete
  end

  # Tag endpoints
  scope "/api/v1/tags", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", TagController, :index
    post "/", TagController, :create
    get "/:id", TagController, :show
    put "/:id", TagController, :update
    delete "/:id", TagController, :delete
  end

  # Group endpoints
  scope "/api/v1/groups", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", GroupController, :index
    post "/", GroupController, :create
    get "/:id", GroupController, :show
    put "/:id", GroupController, :update
    delete "/:id", GroupController, :delete
    get "/:id/entities", GroupController, :list_entities
    post "/:id/entities", GroupController, :add_entities
    delete "/:id/entities/:entity_id", GroupController, :remove_entity
  end

  # Interaction endpoints
  scope "/api/v1/interactions", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", InteractionController, :index
    post "/", InteractionController, :create
    get "/:id", InteractionController, :show
    put "/:id", InteractionController, :update
    delete "/:id", InteractionController, :delete
  end

  # Identifier endpoints
  scope "/api/v1/identifiers", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", IdentifierController, :index
    post "/", IdentifierController, :create
    get "/check", IdentifierController, :check
    get "/:id", IdentifierController, :show
    put "/:id", IdentifierController, :update
    delete "/:id", IdentifierController, :delete
  end

  # External account endpoints
  scope "/api/v1/external-accounts", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", ExternalAccountController, :index
    post "/", ExternalAccountController, :create
    get "/:id", ExternalAccountController, :show
    delete "/:id", ExternalAccountController, :delete
    post "/:id/sync", ExternalAccountController, :sync
    post "/:id/reauth", ExternalAccountController, :reauth
  end

  # Attachment endpoints
  scope "/api/v1/attachments", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    post "/", AttachmentController, :create
    get "/:id", AttachmentController, :show
    get "/:id/download", AttachmentController, :download
    delete "/:id", AttachmentController, :delete
  end

  # Search endpoint
  scope "/api/v1", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/search", SearchController, :search
  end

  # Public health check endpoint (no auth required)
  scope "/api/v1", ConeziaWeb do
    pipe_through [:api]

    get "/health", HealthController, :index
  end

  # Authenticated health endpoints (relationship health)
  scope "/api/v1/health", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/summary", HealthController, :summary
    get "/digest", HealthController, :digest
  end

  # Activity endpoint
  scope "/api/v1", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/activity", ActivityController, :index
  end

  # Import/Export endpoints
  scope "/api/v1", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    post "/import", ImportController, :create
    get "/import/:job_id", ImportController, :show
    post "/import/:job_id/confirm", ImportController, :confirm
    delete "/import/:job_id", ImportController, :delete
    get "/export", ImportController, :export
  end

  # Platform/App endpoints
  scope "/api/v1/apps", ConeziaWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    get "/", AppController, :index
    post "/", AppController, :create
    get "/:id", AppController, :show
    put "/:id", AppController, :update
    delete "/:id", AppController, :delete
    post "/:id/rotate-secret", AppController, :rotate_secret

    get "/:app_id/webhooks", AppController, :list_webhooks
    post "/:app_id/webhooks", AppController, :create_webhook
    get "/:app_id/webhooks/:id", AppController, :show_webhook
    put "/:app_id/webhooks/:id", AppController, :update_webhook
    delete "/:app_id/webhooks/:id", AppController, :delete_webhook
    post "/:app_id/webhooks/:id/test", AppController, :test_webhook
    get "/:app_id/webhooks/:id/deliveries", AppController, :list_deliveries
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:conezia, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ConeziaWeb.Telemetry
    end
  end
end
