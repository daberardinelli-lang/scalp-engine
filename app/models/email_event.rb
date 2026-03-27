class EmailEvent < ApplicationRecord
  belongs_to :lead

  EVENT_TYPES = %w[sent opened clicked bounced opted_out].freeze

  validates :event_type,  inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  scope :by_type,   ->(t) { where(event_type: t) }
  scope :recent,    ->     { order(occurred_at: :desc) }
  scope :sent,      ->     { by_type("sent") }
  scope :opened,    ->     { by_type("opened") }
  scope :clicked,   ->     { by_type("clicked") }
  scope :bounced,   ->     { by_type("bounced") }
  scope :opted_out, ->     { by_type("opted_out") }
end
