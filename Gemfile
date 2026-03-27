source "https://rubygems.org"

ruby File.read(".ruby-version").strip

gem "rails", "~> 8.0"
gem "propshaft"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "redis", "~> 5.0"
gem "solid_queue"
gem "solid_cache"
gem "kamal", require: false
gem "thruster", require: false

# Frontend
gem "tailwindcss-rails"
gem "jsbundling-rails"

# Auth
gem "devise"
gem "pundit"

# Soft delete
gem "discard", "~> 1.4"

# HTTP client per API calls
gem "faraday", "~> 2.0"
gem "faraday-retry"

# Parsing HTML
gem "nokogiri"

# Browser headless per scraping email (Fase 2)
gem "ferrum", "~> 0.15"

# Template engine sicuro per generazione demo HTML
gem "liquid"

# Email
gem "mailgun-ruby", "~> 1.3"

# Rate limiting
gem "rack-attack"

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "web-console"
  gem "rack-mini-profiler"
  gem "annotaterb"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
