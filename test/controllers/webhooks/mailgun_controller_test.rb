# test/controllers/webhooks/mailgun_controller_test.rb
require "test_helper"

class Webhooks::MailgunControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "test_webhook_secret_32chars_xxx"

  setup do
    ENV["MAILGUN_WEBHOOK_SECRET"] = WEBHOOK_SECRET

    @company = create(:company, status: "contacted", email_status: "found")
    @demo    = create(:demo, company: @company)
    @lead    = create(:lead, company: @company, demo: @demo,
                      email_sent_at: 1.hour.ago)
  end

  teardown do
    ENV.delete("MAILGUN_WEBHOOK_SECRET")
  end

  # ─── Helper per costruire payload firmato ──────────────────────────────────

  def signed_payload(event:, extra_event_data: {}, token: @lead.tracking_token)
    timestamp    = Time.current.to_i.to_s
    random_token = SecureRandom.hex(16)
    signature    = OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, "#{timestamp}#{random_token}")

    event_data = {
      "event"          => event,
      "id"             => SecureRandom.uuid,
      "timestamp"      => timestamp.to_f,
      "recipient"      => @company.email,
      "user-variables" => { "tracking_token" => token }
    }.merge(extra_event_data)

    {
      "signature" => {
        "timestamp" => timestamp,
        "token"     => random_token,
        "signature" => signature
      },
      "event-data" => event_data
    }
  end

  def post_webhook(payload)
    post webhooks_mailgun_path, params: payload.to_json,
         headers: { "Content-Type" => "application/json" }
  end

  # ─── Firma ─────────────────────────────────────────────────────────────────

  test "rifiuta richieste con firma non valida" do
    payload = signed_payload(event: "opened")
    payload["signature"]["signature"] = "firma_sbagliata"

    post_webhook(payload)

    assert_response :unauthorized
    assert_equal 0, @lead.email_events.count
  end

  test "rifiuta richieste senza signature block" do
    post webhooks_mailgun_path, params: { "event-data" => { "event" => "opened" } }.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  # ─── Evento: opened ────────────────────────────────────────────────────────

  test "opened: aggiorna email_opened_at e crea EmailEvent" do
    assert_nil @lead.email_opened_at

    post_webhook(signed_payload(event: "opened"))

    assert_response :ok
    @lead.reload
    assert_not_nil @lead.email_opened_at
    assert_equal 1, @lead.email_events.where(event_type: "opened").count
  end

  test "opened: non sovrascrive email_opened_at se già impostato" do
    first_open = 2.hours.ago
    @lead.update!(email_opened_at: first_open)

    post_webhook(signed_payload(event: "opened"))

    assert_response :ok
    @lead.reload
    # Il timestamp deve rimanere il primo
    assert_in_delta first_open, @lead.email_opened_at, 1.second
  end

  test "opened: crea più EmailEvent per aperture multiple (analytics)" do
    post_webhook(signed_payload(event: "opened"))
    post_webhook(signed_payload(event: "opened"))  # seconda apertura

    assert_response :ok
    assert_equal 2, @lead.email_events.where(event_type: "opened").count
  end

  # ─── Evento: clicked ───────────────────────────────────────────────────────

  test "clicked: aggiorna link_clicked_at e crea EmailEvent con url" do
    demo_url = "https://ristorante-mario.demo.webradar.it"

    post_webhook(signed_payload(event: "clicked", extra_event_data: { "url" => demo_url }))

    assert_response :ok
    @lead.reload
    assert_not_nil @lead.link_clicked_at

    event = @lead.email_events.find_by(event_type: "clicked")
    assert_not_nil event
    assert_equal demo_url, event.metadata["url"]
  end

  # ─── Evento: complained / unsubscribed (opt-out) ───────────────────────────

  test "complained: imposta opted_out su lead e company" do
    post_webhook(signed_payload(event: "complained"))

    assert_response :ok
    @lead.reload
    @company.reload
    assert_equal "opted_out", @lead.outcome
    assert_not_nil @company.opted_out_at
    assert_equal "opted_out", @company.status
    assert_equal 1, @lead.email_events.where(event_type: "opted_out").count
  end

  test "unsubscribed: comportamento identico a complained" do
    post_webhook(signed_payload(event: "unsubscribed"))

    assert_response :ok
    @lead.reload
    assert_equal "opted_out", @lead.outcome
    assert_equal 1, @lead.email_events.where(event_type: "opted_out").count
  end

  # ─── Evento: failed / bounced ──────────────────────────────────────────────

  test "failed: crea EmailEvent bounced con reason" do
    extra = {
      "delivery-status" => { "message" => "Mailbox does not exist" }
    }

    post_webhook(signed_payload(event: "failed", extra_event_data: extra))

    assert_response :ok
    event = @lead.email_events.find_by(event_type: "bounced")
    assert_not_nil event
    assert_equal "Mailbox does not exist", event.metadata["reason"]
  end

  # ─── Idempotenza ───────────────────────────────────────────────────────────

  test "non duplica eventi con stesso mailgun_event_id" do
    payload = signed_payload(event: "opened")

    post_webhook(payload)
    post_webhook(payload)  # retry di Mailgun con stesso payload

    assert_response :ok
    # Deve esserci un solo evento nonostante due POST
    assert_equal 1, @lead.email_events.where(event_type: "opened").count
  end

  # ─── Token sconosciuto ─────────────────────────────────────────────────────

  test "risponde 200 per token sconosciuto (non far ritenare a Mailgun)" do
    post_webhook(signed_payload(event: "opened", token: "token_inesistente"))

    assert_response :ok
    assert_equal 0, @lead.email_events.count
  end

  # ─── Evento non gestito ────────────────────────────────────────────────────

  test "risponde 200 per eventi non gestiti come delivered" do
    post_webhook(signed_payload(event: "delivered"))

    assert_response :ok
    assert_equal 0, @lead.email_events.count
  end
end
