ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods
    fixtures :all

    # Helper per creare utenti Devise in test
    def sign_in_as(user)
      post user_session_path, params: {
        user: { email: user.email, password: "password123" }
      }
    end
  end
end
