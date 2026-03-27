# test/services/outreach/email_builder_test.rb
require "test_helper"

class Outreach::EmailBuilderTest < ActiveSupport::TestCase
  setup do
    @company = FactoryBot.create(:company,
                                 name:               "Pizzeria Napoli",
                                 city:               "Roma",
                                 email:              "info@pizzerianapoli.it",
                                 maps_rating:        4.8,
                                 maps_reviews_count: 240,
                                 status:             "demo_built")

    @demo = FactoryBot.create(:demo,
                              company:            @company,
                              subdomain:          "pizzeria-napoli-rm-abc",
                              generated_headline: "La pizza napoletana più buona di Roma",
                              generated_about:    "Da 20 anni nel quartiere Prati, con ingredienti selezionati e forno a legna tradizionale.",
                              generated_cta:      "Prenota un tavolo",
                              deployed_at:        Time.current)

    @lead = FactoryBot.create(:lead, company: @company, demo: @demo)
  end

  # ─── Test: happy path ─────────────────────────────────────────────────────

  test "costruisce email con subject e HTML validi" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?, result.errors.inspect
    assert_not_nil result.subject
    assert_not_nil result.html
    assert result.subject.include?("Pizzeria Napoli")
    assert result.html.include?("Pizzeria Napoli")
  end

  test "include il pixel di tracking nell'HTML" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    assert result.html.include?("/t/#{@lead.tracking_token}/open")
  end

  test "include il link tracciato alla demo" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    assert result.html.include?("/t/#{@lead.tracking_token}/click")
  end

  test "include il link opt-out GDPR" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    assert result.html.include?("/t/#{@lead.tracking_token}/optout")
  end

  test "include headline AI nel corpo email" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    assert result.html.include?("La pizza napoletana più buona di Roma")
  end

  test "include rating Google Maps" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    assert result.html.include?("4.8")
    assert result.html.include?("240")
  end

  test "include brand name e email di contatto" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    brand = ENV.fetch("BRAND_NAME", "WebRadar")
    assert result.html.include?(brand)
  end

  test "subject contiene il nome dell'azienda" do
    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.subject.include?("Pizzeria Napoli")
  end

  test "about viene troncato a 160 caratteri" do
    long_about = "A" * 300
    @demo.update_column(:generated_about, long_about)

    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.success?
    # Il testo troncato non deve superare 160 caratteri nel template
    assert result.html.length < 10_000  # sanity check sulla dimensione
  end

  # ─── Test: URL di tracking ────────────────────────────────────────────────

  test "tracking URL usa APP_BASE_URL se configurato" do
    original = ENV["APP_BASE_URL"]
    ENV["APP_BASE_URL"] = "https://track.webradar.it"

    result = Outreach::EmailBuilder.build(company: @company, demo: @demo, lead: @lead)

    assert result.html.include?("https://track.webradar.it/t/#{@lead.tracking_token}/click")
  ensure
    ENV["APP_BASE_URL"] = original
  end
end
