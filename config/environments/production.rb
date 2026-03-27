require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading  = false
  config.eager_load        = true
  config.consider_all_requests_local = false

  # Active Storage → S3/MinIO produzione
  config.active_storage.service = :minio

  # Logging
  config.log_level = :info
  config.log_tags  = [:request_id]
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Cache
  config.cache_store = :solid_cache_store

  # Assets
  config.assets.compile = false

  # Email
  config.action_mailer.default_url_options = {
    host: ENV.fetch("BRAND_EMAIL_HOST", "webradar.it")
  }

  # Force SSL
  config.force_ssl = true

  # Health check
  config.assume_ssl = true
end
