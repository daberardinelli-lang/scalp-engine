# app/controllers/webhooks/mailgun_controller.rb
#
# Riceve eventi da Mailgun via webhook (opened, clicked, bounced, complained, failed).
# Verifica la firma HMAC-SHA256 prima di processare qualsiasi dato.
# Risponde sempre 200 per evitare retry da parte di Mailgun.
#
# Configurazione Mailgun:
#   - Dashboard → Sending → Webhooks → aggiungere la URL: https://app.webradar.it/webhooks/mailgun
#   - Abilitare: opened, clicked, bounced, complained, unsubscribed, failed
#   - MAILGUN_WEBHOOK_SECRET: visibile in Sending → Webhooks → "Webhook signing key"
#
# Payload atteso (Mailgun API v3):
#   {
#     "signature": { "timestamp": "...", "token": "...", "signature": "..." },
#     "event-data": {
#       "event":          "opened",        # opened | clicked | failed | complained | unsubscribed
#       "id":             "<event_uuid>",  # id univoco Mailgun — usato per idempotenza
#       "timestamp":      1529006854.53,
#       "recipient":      "info@esempio.it",
#       "url":            "https://...",   # solo per "clicked"
#       "user-variables": { "tracking_token": "abc123" },
#       "delivery-status": { "message": "..." }  # solo per "failed"
#     }
#   }
#
class Webhooks::MailgunController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /webhooks/mailgun
  def create
    unless valid_signature?
      Rails.logger.warn "[MailgunWebhook] Firma non valida — richiesta rifiutata"
      return head :unauthorized
    end

    event_data  = params["event-data"] || {}
    event_name  = event_data["event"].to_s
    user_vars   = event_data["user-variables"] || {}
    token       = user_vars["tracking_token"].to_s
    occurred_at = parse_timestamp(event_data["timestamp"])
    mg_event_id = event_data["id"].to_s

    unless token.present?
      Rails.logger.info "[MailgunWebhook] Evento #{event_name} senza tracking_token — ignorato"
      return head :ok
    end

    lead = Lead.find_by(tracking_token: token)
    unless lead
      Rails.logger.warn "[MailgunWebhook] Lead non trovato per token #{token} (event: #{event_name})"
      return head :ok
    end

    handle_event(lead, event_name, occurred_at, event_data, mg_event_id)
    head :ok
  rescue => e
    Rails.logger.error "[MailgunWebhook] #{e.class}: #{e.message}"
    head :ok  # sempre 200 per evitare retry Mailgun
  end

  private

  # Verifica la firma HMAC-SHA256 di Mailgun.
  # Algoritmo: HMAC-SHA256(key: MAILGUN_WEBHOOK_SECRET, data: timestamp + token)
  def valid_signature?
    sig_params = params[:signature] || {}
    timestamp  = sig_params[:timestamp].to_s
    token      = sig_params[:token].to_s
    signature  = sig_params[:signature].to_s

    return false if [timestamp, token, signature].any?(&:empty?)

    secret   = ENV.fetch("MAILGUN_WEBHOOK_SECRET", "")
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}#{token}")
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def parse_timestamp(raw)
    Time.at(raw.to_f)
  rescue
    Time.current
  end

  # Controlla se questo specifico evento Mailgun è già stato processato (idempotenza).
  def already_processed?(lead, mg_event_id)
    return false if mg_event_id.blank?

    lead.email_events.where("metadata->>'mailgun_event_id' = ?", mg_event_id).exists?
  end

  def handle_event(lead, event_name, occurred_at, event_data, mg_event_id)
    return if already_processed?(lead, mg_event_id)

    metadata = {
      mailgun_event_id: mg_event_id,
      raw_event:        event_name,
      recipient:        event_data["recipient"].to_s
    }

    case event_name
    when "opened"
      # Aggiorna solo alla prima apertura; le successive vengono registrate come eventi
      lead.update!(email_opened_at: occurred_at) unless lead.opened?
      create_email_event(lead, "opened", occurred_at, metadata)
      Rails.logger.info "[MailgunWebhook] 👁 Aperta — #{lead.company.name}"

    when "clicked"
      url = event_data["url"].to_s
      lead.update!(link_clicked_at: occurred_at) unless lead.clicked?
      create_email_event(lead, "clicked", occurred_at, metadata.merge(url: url))
      Rails.logger.info "[MailgunWebhook] 🖱 Click — #{lead.company.name} → #{url}"

    when "complained", "unsubscribed"
      # Opt-out: il destinatario ha segnato l'email come spam o si è disiscritto
      lead.update!(outcome: "opted_out")
      lead.company.update!(opted_out_at: occurred_at, status: "opted_out")
      create_email_event(lead, "opted_out", occurred_at, metadata)
      Rails.logger.info "[MailgunWebhook] 🚫 Opt-out (#{event_name}) — #{lead.company.name}"

    when "failed", "bounced"
      reason = event_data.dig("delivery-status", "message").to_s
      create_email_event(lead, "bounced", occurred_at, metadata.merge(reason: reason))
      Rails.logger.warn "[MailgunWebhook] ⚠ Bounce (#{event_name}) — #{lead.company.name}: #{reason}"

    else
      Rails.logger.info "[MailgunWebhook] Evento non gestito: #{event_name}"
    end
  end

  def create_email_event(lead, event_type, occurred_at, metadata)
    lead.email_events.create!(
      event_type:  event_type,
      occurred_at: occurred_at,
      metadata:    metadata
    )
  end
end
