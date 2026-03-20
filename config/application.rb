require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module Webradar
  class Application < Rails::Application
    config.load_defaults 8.0

    # Solid Queue come adapter per Active Job
    config.active_job.queue_adapter = :solid_queue

    # Timezone
    config.time_zone = "Rome"
    config.i18n.default_locale = :it
    config.i18n.available_locales = [:it, :en]

    # Generators default
    config.generators do |g|
      g.test_framework  :minitest
      g.stylesheets     false
      g.javascripts     false
      g.helper          false
      g.jbuilder        false
    end

    # Rate limiting
    config.middleware.use Rack::Attack

    # Filtra params sensibili dai log
    config.filter_parameters += %i[
      passw secret token key credential
      google_places anthropic sendgrid mailgun optout
    ]
  end
end
