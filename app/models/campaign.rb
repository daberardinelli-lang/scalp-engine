class Campaign < ApplicationRecord
  belongs_to :user, optional: true
  has_many :companies, dependent: :nullify

  MODES             = %w[outreach web_agency].freeze
  DISCOVERY_SOURCES = %w[google_places pagine_gialle web_scraping].freeze

  # Template email predefiniti disponibili
  EMAIL_TEMPLATES = %w[
    web_agency
    commercial_rep
    pharma_rep
  ].freeze

  validates :name,             presence: true
  validates :discovery_source, inclusion: { in: DISCOVERY_SOURCES }
  validates :mode,             inclusion: { in: MODES }

  scope :active,      -> { where(active: true) }
  scope :ordered,     -> { order(created_at: :desc) }
  scope :outreach,    -> { where(mode: "outreach") }
  scope :web_agency,  -> { where(mode: "web_agency") }

  def outreach?   = mode == "outreach"
  def web_agency? = mode == "web_agency"

  # Per outreach: include tutti i prospect (anche con sito web)
  def skip_websites? = web_agency?

  # Etichetta leggibile per la fonte di discovery
  def discovery_source_label
    {
      "google_places"  => "Google Places",
      "pagine_gialle"  => "Pagine Gialle",
      "web_scraping"   => "Web Scraping"
    }[discovery_source] || discovery_source
  end

  # Path completo al template email Liquid
  def email_template_path
    template = email_body_template.presence || "web_agency"
    Rails.root.join("app", "views", "outreach", "templates", "#{template}.html.liquid").to_s
  end

  # Subject con fallback generico
  def resolved_subject_template
    email_subject_template.presence ||
      "{{ company_name }} — abbiamo una proposta per voi 🎯"
  end
end
