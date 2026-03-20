class User < ApplicationRecord
  include Discard::Model

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { operator: "operator", admin: "admin" }

  validates :first_name, presence: true
  validates :last_name,  presence: true

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    role == "admin"
  end
end
