class Lead < ApplicationRecord
  belongs_to :company
  belongs_to :demo, optional: true
  has_many   :email_events, dependent: :destroy

  OUTCOMES = %w[pending interested not_interested converted opted_out].freeze

  validates :outcome,        inclusion: { in: OUTCOMES }
  validates :tracking_token, presence: true, uniqueness: true

  before_validation :generate_tracking_token, on: :create

  scope :sent,      -> { where.not(email_sent_at: nil) }
  scope :opened,    -> { where.not(email_opened_at: nil) }
  scope :clicked,   -> { where.not(link_clicked_at: nil) }
  scope :replied,   -> { where.not(replied_at: nil) }
  scope :hot,       -> { clicked.where(outcome: %w[pending interested]) }

  def open_rate_eligible?
    email_sent_at.present?
  end

  def opened?
    email_opened_at.present?
  end

  def clicked?
    link_clicked_at.present?
  end

  def replied?
    replied_at.present?
  end

  private

  def generate_tracking_token
    self.tracking_token ||= SecureRandom.urlsafe_base64(24)
  end
end
