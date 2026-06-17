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

  # Servizi normalizzati ad array di hash {"name", "desc"}.
  # `generated_services` può contenere due formati:
  #   - nuovo:  [{"name": "...", "desc": "..."}, ...]
  #   - vecchio: ["nome1", "nome2", ...]  (demo precedenti → desc vuota)
  def services_detailed
    parse_generated_services.map do |s|
      if s.is_a?(Hash)
        { "name" => s["name"].to_s, "desc" => s["desc"].to_s }
      else
        { "name" => s.to_s, "desc" => "" }
      end
    end
  end

  # Solo i nomi dei servizi (retrocompat: viste admin, ecc.)
  def services_list
    services_detailed.map { |s| s["name"] }
  end

  def content_generated?
    generated_headline.present? && generated_about.present?
  end

  # Parsa `generated_services` (text JSON) in array grezzo (hash o stringhe).
  def parse_generated_services
    return [] if generated_services.blank?
    parsed = JSON.parse(generated_services)
    parsed.is_a?(Array) ? parsed : [generated_services]
  rescue JSON::ParserError
    [generated_services]
  end
  private :parse_generated_services

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
