# app/services/outreach/mailhog_service.rb
#
# Consegna email via SMTP a MailHog in SVILUPPO, così il flusso di outreach è
# testabile in locale senza Mailgun. Le email finiscono nella UI MailHog
# (http://localhost:8025). In produzione si usa Outreach::MailgunService.
#
# Espone la stessa interfaccia Result di MailgunService (success?/message_id/errors)
# così è intercambiabile nel job senza modifiche.
#
require "mail"

module Outreach
  class MailhogService
    Result = Struct.new(:message_id, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    def self.send_email(to:, subject:, html:, from: nil, tracking_token: nil)
      mail = Mail.new
      mail.from         = from || default_from
      mail.to           = to
      mail.subject      = subject
      mail.content_type = "text/html; charset=UTF-8"
      mail.body         = html
      mail["X-WebRadar-Tracking-Token"] = tracking_token if tracking_token.present?

      mail.delivery_method :smtp,
        address:              ENV.fetch("MAILHOG_HOST", "mailhog"),
        port:                 ENV.fetch("MAILHOG_SMTP_PORT", "1025").to_i,
        enable_starttls_auto: false,
        open_timeout:         5,
        read_timeout:         5

      mail.deliver!

      Rails.logger.info "[MailhogService] (DEV) email a #{to} consegnata a MailHog"
      Result.new(message_id: mail.message_id || "mailhog-dev", errors: [])
    rescue => e
      Rails.logger.error "[MailhogService] #{e.class}: #{e.message}"
      Result.new(message_id: nil, errors: ["MailHog delivery error: #{e.message}"])
    end

    def self.default_from
      "#{ENV.fetch('BRAND_NAME', 'WebRadar')} <#{ENV.fetch('BRAND_EMAIL', 'info@webradar.it')}>"
    end
  end
end
