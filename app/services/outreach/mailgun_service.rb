# app/services/outreach/mailgun_service.rb
#
# Invia email transazionali via Mailgun HTTP API.
# Il client Mailgun è iniettabile per facilitare i test.
#
# Uso:
#   result = Outreach::MailgunService.send_email(to:, subject:, html:)
#   result.success?    # => true
#   result.message_id  # => "<xyz@mailgun.org>"
#
module Outreach
  class MailgunService
    Result = Struct.new(:message_id, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    def self.send_email(to:, subject:, html:, from: nil, tracking_token: nil, mg_client: nil)
      new(mg_client: mg_client).send_email(
        to: to, subject: subject, html: html,
        from: from, tracking_token: tracking_token
      )
    end

    def initialize(mg_client: nil)
      @mg_client = mg_client
    end

    def send_email(to:, subject:, html:, from: nil, tracking_token: nil)
      client       = @mg_client || build_client
      from_address = from || default_from

      message_params = {
        from:           from_address,
        to:             to,
        subject:        subject,
        html:           html,
        "o:tracking"  => "no",   # tracking gestito internamente con pixel e redirect
        "o:tag"       => "outreach"
      }

      # Variabile custom Mailgun → usata dai webhook per identificare il Lead
      if tracking_token.present?
        message_params["v:tracking_token"] = tracking_token
      end

      response   = client.send_message(mailgun_domain, message_params)
      message_id = response.to_h["id"]

      Rails.logger.info "[MailgunService] Email inviata a #{to} (#{message_id})"
      Result.new(message_id: message_id, errors: [])
    rescue Mailgun::CommunicationError => e
      Rails.logger.error "[MailgunService] CommunicationError: #{e.message}"
      Result.new(message_id: nil, errors: ["Mailgun API error: #{e.message}"])
    rescue KeyError => e
      Result.new(message_id: nil, errors: ["Config mancante: #{e.message}"])
    rescue => e
      Rails.logger.error "[MailgunService] #{e.class}: #{e.message}"
      Result.new(message_id: nil, errors: ["MailgunService error: #{e.message}"])
    end

    private

    def build_client
      Mailgun::Client.new(ENV.fetch("MAILGUN_API_KEY"))
    end

    def mailgun_domain
      ENV.fetch("MAILGUN_DOMAIN")
    end

    def default_from
      brand = ENV.fetch("BRAND_NAME", "WebRadar")
      email = ENV.fetch("BRAND_EMAIL", "info@webradar.it")
      "#{brand} <#{email}>"
    end
  end
end
