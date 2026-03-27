require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # Active Storage → MinIO in sviluppo
  config.active_storage.service = :minio

  # Email → MailHog in sviluppo
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("MAILHOG_HOST", "mailhog"),
    port: 1025
  }
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # Logging
  config.log_level = :debug
  config.log_tags  = [:request_id]
  config.logger    = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))

  # Cache in sviluppo (memory store)
  config.cache_store = :memory_store

  # Assets
  config.assets.debug   = true
  config.assets.quiet   = true

  # I18n — non sollevare eccezione per traduzioni mancanti in sviluppo
  config.i18n.raise_on_missing_translations = false

  # Annotate rendered view with file names
  config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error on missing translations
  config.action_controller.raise_on_missing_callback_actions = true
end
