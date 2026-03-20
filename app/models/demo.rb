class Demo < ApplicationRecord
  belongs_to :company
  has_many   :leads, dependent: :nullify

  validates :subdomain, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: "solo lettere minuscole, numeri e trattini" }

  scope :deployed,  -> { where.not(deployed_at: nil) }
  scope :active,    -> { deployed.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired,   -> { where("expires_at <= ?", Time.current) }

  def url
    "https://#{subdomain}.#{ENV.fetch("DEMO_BASE_DOMAIN", "demo.webradar.it")}"
  end

  def deployed?
    deployed_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    deployed? && !expired?
  end

  def register_view!
    update_columns(
      view_count:    (view_count || 0) + 1,
      last_viewed_at: Time.current
    )
  end

  # Deserializza i servizi generati (colonna text JSON-encoded)
  def services_list
    return [] if generated_services.blank?
    parsed = JSON.parse(generated_services)
    parsed.is_a?(Array) ? parsed : [generated_services]
  rescue JSON::ParserError
    [generated_services]
  end

  def content_generated?
    generated_headline.present? && generated_about.present?
  end

  # Genera lo slug dal nome azienda
  def self.slugify(name)
    name
      .downcase
      .gsub(/[àáâãäå]/, "a").gsub(/[èéêë]/, "e")
      .gsub(/[ìíîï]/, "i").gsub(/[òóôõö]/, "o")
      .gsub(/[ùúûü]/, "u")
      .gsub(/[^a-z0-9\s\-]/, "")
      .gsub(/\s+/, "-")
      .gsub(/-+/, "-")
      .strip
      .first(50)
  end
end
