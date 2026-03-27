# test/services/content/generator_service_test.rb
require "test_helper"

class Content::GeneratorServiceTest < ActiveSupport::TestCase
  # ─── JSON di risposta Claude simulato ─────────────────────────────────────

  VALID_CONTENT = {
    "headline"  => "Ristorante Bella Italia — Il gusto autentico di Prato",
    "about"     => "Da oltre 30 anni portiamo in tavola la tradizione culinaria toscana. " \
                   "I nostri piatti sono preparati con ingredienti locali selezionati con cura.",
    "services"  => %w[Pranzo\ di\ lavoro Cena\ romantica Banchetti Pizza\ artigianale],
    "cta"       => "Prenota il tuo tavolo"
  }.freeze

  CLAUDE_SUCCESS_BODY = JSON.generate({
    "content" => [
      { "type" => "thinking", "thinking" => "Analizzo l'azienda..." },
      { "type" => "text",     "text"     => JSON.generate(VALID_CONTENT) }
    ]
  }).freeze

  CLAUDE_MISSING_FIELDS_BODY = JSON.generate({
    "content" => [
      { "type" => "text", "text" => JSON.generate({ "headline" => "Solo headline" }) }
    ]
  }).freeze

  CLAUDE_INVALID_JSON_BODY = JSON.generate({
    "content" => [
      { "type" => "text", "text" => "non sono JSON valido" }
    ]
  }).freeze

  CLAUDE_NO_TEXT_BLOCK_BODY = JSON.generate({
    "content" => [
      { "type" => "thinking", "thinking" => "..." }
    ]
  }).freeze

  # ─── Setup ────────────────────────────────────────────────────────────────

  setup do
    @company = FactoryBot.create(:company,
                                 name:            "Ristorante Bella Italia",
                                 city:            "Prato",
                                 province:        "PO",
                                 category:        "restaurant",
                                 maps_rating:     4.5,
                                 maps_reviews_count: 120,
                                 status:          "enriched",
                                 opted_out_at:    nil)
  end

  # ─── Test: flusso happy path ──────────────────────────────────────────────

  test "genera contenuti e crea Demo con status demo_built" do
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_SUCCESS_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    assert result.success?, "deve avere successo: #{result.errors.inspect}"
    assert_not_nil result.demo

    demo = result.demo
    assert_equal VALID_CONTENT["headline"], demo.generated_headline
    assert_equal VALID_CONTENT["about"],    demo.generated_about
    assert_equal VALID_CONTENT["cta"],      demo.generated_cta
    assert_equal VALID_CONTENT["services"], demo.services_list
    assert_not_nil demo.subdomain
    assert demo.expires_at > Time.current

    @company.reload
    assert_equal "demo_built", @company.status
  end

  test "aggiorna demo esistente se la company ha già un demo" do
    existing_demo = FactoryBot.create(:demo, company: @company, subdomain: "bella-italia-prato-abc123")
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_SUCCESS_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    assert result.success?
    assert_equal existing_demo.id, result.demo.id
    assert_equal VALID_CONTENT["headline"], result.demo.reload.generated_headline
    # subdomain deve restare invariato (già valido)
    assert_equal "bella-italia-prato-abc123", result.demo.subdomain
  end

  # ─── Test: errori API ─────────────────────────────────────────────────────

  test "ritorna errore se Claude risponde con status non 200" do
    error_body = JSON.generate({ "error" => { "message" => "Rate limit exceeded" } })
    client = build_test_client { |stub| stub.post { [429, {}, error_body] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("Claude API error 429") }
  end

  test "ritorna errore HTTP se Faraday solleva eccezione" do
    client = build_test_client { |stub| stub.post { raise Faraday::ConnectionFailed, "Connection refused" } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("HTTP error Claude API") }
  end

  # ─── Test: parsing risposta ───────────────────────────────────────────────

  test "ritorna errore se risposta manca di campi richiesti" do
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_MISSING_FIELDS_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("campi richiesti") }
  end

  test "ritorna errore se risposta non è JSON valido" do
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_INVALID_JSON_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("JSON parsing error") }
  end

  test "ritorna errore se non c'è blocco text nella risposta" do
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_NO_TEXT_BLOCK_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("blocco 'text'") }
  end

  test "strip markdown code block delimiters dalla risposta" do
    body_with_markdown = JSON.generate({
      "content" => [
        { "type" => "text", "text" => "```json\n#{JSON.generate(VALID_CONTENT)}\n```" }
      ]
    })
    client = build_test_client { |stub| stub.post { [200, {}, body_with_markdown] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    assert result.success?, "deve gestire il markdown: #{result.errors.inspect}"
  end

  # ─── Test: validazione company ────────────────────────────────────────────

  test "skip se company non è in stato enriched o demo_built" do
    @company.update_column(:status, "discovered")
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_SUCCESS_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("enriched") || e.include?("demo_built") }
  end

  test "skip se company ha fatto opt-out" do
    @company.update_column(:opted_out_at, Time.current)
    client = build_test_client { |stub| stub.post { [200, {}, CLAUDE_SUCCESS_BODY] } }

    result = Content::GeneratorService.call(company: @company, http_client: client)

    refute result.success?
    assert result.errors.any? { |e| e.include?("opt-out") }
  end

  # ─── Test: Demo#services_list ─────────────────────────────────────────────

  test "Demo#services_list deserializza JSON correttamente" do
    demo = Demo.new(generated_services: JSON.generate(["Pizza", "Pasta", "Antipasti"]))
    assert_equal ["Pizza", "Pasta", "Antipasti"], demo.services_list
  end

  test "Demo#services_list ritorna array vuoto se blank" do
    demo = Demo.new(generated_services: nil)
    assert_equal [], demo.services_list
  end

  test "Demo#content_generated? ritorna true se headline e about presenti" do
    demo = Demo.new(generated_headline: "Titolo", generated_about: "Descrizione")
    assert demo.content_generated?
  end

  test "Demo#content_generated? ritorna false se headline mancante" do
    demo = Demo.new(generated_headline: nil, generated_about: "Descrizione")
    refute demo.content_generated?
  end

  private

  def build_test_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new(url: "https://api.anthropic.com") { |f| f.adapter :test, stubs }
  end
end
