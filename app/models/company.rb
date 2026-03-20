class Company < ApplicationRecord
  include Discard::Model

  has_one  :demo,  dependent: :destroy
  has_many :leads, dependent: :destroy

  CATEGORIES = %w[
    restaurant bar pizzeria
    plumber electrician builder
    retail shop
    lawyer accountant notary
    other
  ].freeze

  STATUSES = %w[
    discovered enriched demo_built contacted replied converted opted_out
  ].freeze

  EMAIL_STATUSES = %w[found manual skip unknown].freeze

  validates :name,     presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status,   inclusion: { in: STATUSES }

  scope :active,           -> { kept.where(opted_out_at: nil) }
  scope :without_website,  -> { where(has_website: false) }
  scope :with_email,       -> { where(email_status: "found") }
  scope :contactable,      -> { active.without_website.with_email.where(status: %w[enriched demo_built]) }
  scope :by_province,      ->(p)   { where(province: p) }
  scope :by_category,      ->(cat) { where(category: cat) }

  def opted_out?
    opted_out_at.present?
  end

  def contactable?
    !opted_out? && !discarded? && !has_website? && email_status == "found"
  end

  def pipeline_step
    STATUSES.index(status) || 0
  end

  def full_address
    [address, city, province].compact.join(", ")
  end

  def category_label
    I18n.t("webradar.categories.#{category}", default: category.humanize)
  end

  # ─── Reviews helpers (Fase 2) ─────────────────────────────────────────────

  def average_review_rating
    return nil if reviews_data.blank?

    ratings = reviews_data.map { |r| r["rating"].to_f }.select(&:positive?)
    return nil if ratings.empty?

    (ratings.sum / ratings.size).round(1)
  end

  def best_reviews(limit: 3)
    return [] if reviews_data.blank?

    reviews_data
      .select { |r| r["text"].present? && r["rating"].to_i >= 4 }
      .sort_by { |r| -r["rating"].to_i }
      .first(limit)
  end

  def enriched?
    status != "discovered"
  end
end
