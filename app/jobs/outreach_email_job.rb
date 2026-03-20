# app/jobs/outreach_email_job.rb
#
# Invia l'email di outreach a una singola azienda.
# Gestisce: creazione Lead, build HTML, invio Mailgun, aggiornamento stati.
#
# Uso:
#   OutreachEmailJob.perform_later(company_id: 42)
#
class OutreachEmailJob < ApplicationJob
  queue_as :email

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(company_id:)
    company = Company.kept.find(company_id)

    # ── Validazioni pre-invio ───────────────────────────────────────────────
    unless company.contactable?
      Rails.logger.warn "[OutreachEmailJob] Skip #{company.name}: non contattabile " \
                        "(opted_out=#{company.opted_out?}, has_website=#{company.has_website?}, " \
                        "email_status=#{company.email_status})"
      return
    end

    demo = company.demo
    unless demo&.content_generated?
      Rails.logger.warn "[OutreachEmailJob] Skip #{company.name}: contenuti demo non generati"
      return
    end

    unless demo.deployed?
      Rails.logger.warn "[OutreachEmailJob] Skip #{company.name}: demo HTML non ancora deployata"
      return
    end

    # ── Crea / aggiorna Lead ────────────────────────────────────────────────
    lead = Lead.find_or_initialize_by(company: company)
    lead.demo    = demo
    lead.outcome = "pending" if lead.new_record?
    lead.save!

    # ── Costruisci email ────────────────────────────────────────────────────
    email_result = Outreach::EmailBuilder.build(company: company, demo: demo, lead: lead)
    unless email_result.success?
      raise "EmailBuilder failed for #{company.name}: #{email_result.errors.join(', ')}"
    end

    # ── Invia via Mailgun ───────────────────────────────────────────────────
    send_result = Outreach::MailgunService.send_email(
      to:             company.email,
      subject:        email_result.subject,
      html:           email_result.html,
      tracking_token: lead.tracking_token
    )
    unless send_result.success?
      raise "MailgunService failed for #{company.name}: #{send_result.errors.join(', ')}"
    end

    # ── Registra invio ──────────────────────────────────────────────────────
    lead.update!(
      email_sent_at:       Time.current,
      email_subject:       email_result.subject,
      email_body_snapshot: email_result.html,
      provider_message_id: send_result.message_id
    )

    lead.email_events.create!(
      event_type:  "sent",
      occurred_at: Time.current,
      metadata:    { message_id: send_result.message_id, to: company.email }
    )

    # ── Avanza stato azienda ────────────────────────────────────────────────
    company.update!(status: "contacted")

    Rails.logger.info "[OutreachEmailJob] ✓ #{company.name} <#{company.email}>"
  end
end
