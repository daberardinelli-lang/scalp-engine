Rails.application.routes.draw do
  devise_for :users, path: "auth", path_names: {
    sign_in:  "login",
    sign_out: "logout",
    sign_up:  "register"
  }

  authenticated :user do
    root to: redirect("/admin/contatti"), as: :authenticated_root
  end

  root to: redirect("/auth/login")

  # Tracking email (no auth — chiamati da pixel/link nelle email)
  get  "/t/:token/open",    to: "tracking#open",    as: :track_open
  get  "/t/:token/click",   to: "tracking#click",   as: :track_click
  get  "/t/:token/optout",  to: "tracking#opt_out", as: :track_opt_out

  # Dashboard
  namespace :admin do
    # Sezione Contatti (outreach/campagne)
    get  "contatti",            to: "companies#contatti",       as: :contatti
    get  "contatti/export",     to: "companies#export_xlsx",    as: :contatti_export, defaults: { mode: "outreach" }

    # Sezione Software Agency (demo siti)
    get  "software-agency",           to: "companies#software_agency",  as: :software_agency
    get  "software-agency/export",    to: "companies#export_xlsx",      as: :software_agency_export, defaults: { mode: "web_agency" }

    resources :companies, only: [:show] do
      collection do
        post :discover
        post :batch_enrich
        post :batch_generate
        post :batch_build
        post :batch_email
        get  :export_xlsx
      end
      member do
        post :enrich
        post :generate_content
        post :build_demo
        post :send_email
        post :mark_replied
        post :mark_converted
        patch :update_contact
        patch :restore_email
      end
    end
    resources :leads,     only: [:index, :show]
    resources :demos,     only: [:index, :show]
    resources :campaigns, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :toggle_active
      end
    end
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
