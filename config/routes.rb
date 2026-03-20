Rails.application.routes.draw do
  devise_for :users, path: "auth", path_names: {
    sign_in:  "login",
    sign_out: "logout",
    sign_up:  "register"
  }

  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  root to: redirect("/auth/login")

  # Tracking email (no auth — chiamati da pixel/link nelle email)
  get  "/t/:token/open",    to: "tracking#open",    as: :track_open
  get  "/t/:token/click",   to: "tracking#click",   as: :track_click
  get  "/t/:token/optout",  to: "tracking#opt_out", as: :track_opt_out

  # Dashboard
  namespace :admin do
    resources :companies, only: [:index, :show] do
      collection do
        post :discover         # avvia DiscoveryJob (Google Places)
        post :batch_enrich     # avvia EnrichmentJob su tutte le discovered
        post :batch_generate   # avvia ContentGenerationJob su tutte le enriched
        post :batch_build      # avvia DemoBuildJob su tutte le demo_built
        post :batch_email      # avvia OutreachEmailJob su tutte le contattabili
      end
      member do
        post :enrich           # avvia EnrichmentJob su singola company
        post :generate_content # avvia ContentGenerationJob su singola company
        post :build_demo       # avvia DemoBuildJob su singola company
        post :send_email       # avvia OutreachEmailJob su singola company
        post :mark_replied
        post :mark_converted
      end
    end
    resources :leads,  only: [:index, :show]
    resources :demos,  only: [:index, :show]
  end

  # Preview demo HTML in sviluppo (in produzione: nginx wildcard subdomain)
  get "/demos/:subdomain", to: "demo_previews#show", as: :demo_preview,
      constraints: { subdomain: /[a-z0-9\-]+/ }

  # Mailgun Webhooks (no CSRF, no auth — firmati con HMAC-SHA256)
  namespace :webhooks do
    post :mailgun, to: "mailgun#create"
  end

  # Pagine statiche pubbliche (no auth)
  get "/privacy", to: "pages#privacy", as: :privacy_policy

  # Health check per Docker / Kamal
  get "/up", to: proc { [200, {}, ["OK"]] }
end
