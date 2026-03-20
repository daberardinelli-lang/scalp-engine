# test/services/outreach/mailgun_service_test.rb
require "test_helper"

class Outreach::MailgunServiceTest < ActiveSupport::TestCase
  # Fake Mailgun client per i test (nessuna chiamata di rete reale)
  FakeMgResponse = Struct.new(:body) do
    def to_h = JSON.parse(body)
  end

  def fake_mg_client(success: true, message_id: "<abc123@mailgun.org>")
    if success
      response = FakeMgResponse.new(JSON.generate({ "id" => message_id, "message" => "Queued. Thank you." }))
      Module.new do
        define_singleton_method(:send_message) { |_domain, _params| response }
      end
    else
      Module.new do
        define_singleton_method(:send_message) { |_domain, _params|
          raise Mailgun::CommunicationError, "Connection refused"
        }
      end
    end
  end

  # ─── Test: happy path ─────────────────────────────────────────────────────

  test "invia email e restituisce message_id" do
    client = fake_mg_client(success: true, message_id: "<test-msg-id@mailgun.org>")

    result = Outreach::MailgunService.send_email(
      to:        "info@esempio.it",
      subject:   "Test email",
      html:      "<p>Ciao</p>",
      mg_client: client
    )

    assert result.success?, result.errors.inspect
    assert_equal "<test-msg-id@mailgun.org>", result.message_id
  end

  # ─── Test: errori ────────────────────────────────────────────────────────

  test "restituisce errore se Mailgun solleva CommunicationError" do
    client = fake_mg_client(success: false)

    result = Outreach::MailgunService.send_email(
      to:        "info@esempio.it",
      subject:   "Test",
      html:      "<p>Test</p>",
      mg_client: client
    )

    refute result.success?
    assert result.errors.any? { |e| e.include?("Mailgun API error") }
    assert_nil result.message_id
  end

  test "restituisce errore se MAILGUN_DOMAIN non configurato" do
    original = ENV["MAILGUN_DOMAIN"]
    ENV.delete("MAILGUN_DOMAIN")

    # Con mg_client injectable non ha bisogno dell'API key, ma ha bisogno del domain
    client = fake_mg_client(success: true)

    result = Outreach::MailgunService.new(mg_client: client).send_email(
      to:      "info@esempio.it",
      subject: "Test",
      html:    "<p>Test</p>"
    )

    refute result.success?
    assert result.errors.any? { |e| e.include?("Config") || e.include?("MAILGUN_DOMAIN") }
  ensure
    ENV["MAILGUN_DOMAIN"] = original
  end
end
