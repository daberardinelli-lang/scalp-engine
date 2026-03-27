require "test_helper"

class Discovery::Strategies::PagineGialleStrategyTest < ActiveSupport::TestCase
  # ─── HTML di esempio ─────────────────────────────────────────────────────

  SEARCH_HTML_WITH_RESULT = <<~HTML
    <html><body>
      <div class="listing">
        <h2><a class="listing-item__name" href="/pg/ristorante-bella-italia/prato-po">Ristorante Bella Italia</a></h2>
      </div>
    </body></html>
  HTML

  DETAIL_HTML_WITH_MAILTO = <<~HTML
    <html><body>
      <div class="contact">
        <a href="mailto:info@bellaitalia.it">info@bellaitalia.it</a>
      </div>
    </body></html>
  HTML

  DETAIL_HTML_WITH_TEXT_EMAIL = <<~HTML
    <html><body>
      <div class="contact">
        <p>Contattaci a: info@bellaitalia.it per informazioni</p>
      </div>
    </body></html>
  HTML

  DETAIL_HTML_NO_EMAIL = <<~HTML
    <html><body>
      <div class="contact"><p>Chiamaci al 0574 123456</p></div>
    </body></html>
  HTML

  SEARCH_HTML_NO_RESULTS = "<html><body><p>Nessun risultato</p></body></html>"

  # ─── Setup ───────────────────────────────────────────────────────────────

  setup do
    @company = FactoryBot.build(:company,
                                name:     "Ristorante Bella Italia",
                                city:     "Prato",
                                province: "PO")
  end

  # ─── Test ────────────────────────────────────────────────────────────────

  test "trova email da link mailto nella pagina di dettaglio" do
    client = build_test_client do |stub|
      stub.get { [200, {}, DETAIL_HTML_WITH_MAILTO] }
    end

    # Override find_first_listing_url per restituire direttamente un URL
    strategy = strategy_with_direct_detail(client, "https://www.paginegialle.it/pg/test")
    result   = strategy.call

    assert_not_nil result
    assert_equal "info@bellaitalia.it", result["email"]
    assert_equal "paginegialle",        result["source"]
  end

  test "trova email da testo visibile nella pagina" do
    client = build_test_client do |stub|
      stub.get { [200, {}, DETAIL_HTML_WITH_TEXT_EMAIL] }
    end

    strategy = strategy_with_direct_detail(client, "https://www.paginegialle.it/pg/test")
    result   = strategy.call

    assert_not_nil result
    assert_equal "info@bellaitalia.it", result["email"]
  end

  test "ritorna nil se nessuna email trovata" do
    client = build_test_client do |stub|
      stub.get { [200, {}, DETAIL_HTML_NO_EMAIL] }
    end

    strategy = strategy_with_direct_detail(client, "https://www.paginegialle.it/pg/test")
    result   = strategy.call

    assert_nil result
  end

  test "ritorna nil se nessun listing trovato nella ricerca" do
    client = build_test_client do |stub|
      stub.get { [200, {}, SEARCH_HTML_NO_RESULTS] }
    end

    strategy = Discovery::Strategies::PagineGialleStrategy.new(
      company: @company, http_client: client
    )
    result = strategy.call

    assert_nil result
  end

  test "ritorna nil se HTTP fallisce" do
    client = build_test_client do |stub|
      stub.get { raise Faraday::ConnectionFailed, "Connection refused" }
    end

    strategy = Discovery::Strategies::PagineGialleStrategy.new(
      company: @company, http_client: client
    )
    result = strategy.call

    assert_nil result
  end

  test "valida e rifiuta email di domini esclusi" do
    strategy = Discovery::Strategies::PagineGialleStrategy.new(company: @company)

    refute strategy.send(:valid_email?, "info@paginegialle.it")
    refute strategy.send(:valid_email?, "noreply@facebook.com")
    refute strategy.send(:valid_email?, "not-an-email")
    refute strategy.send(:valid_email?, "")
    refute strategy.send(:valid_email?, nil)

    assert strategy.send(:valid_email?, "info@ristorantebellaitalia.it")
    assert strategy.send(:valid_email?, "contatto@studio-legale.com")
  end

  private

  def build_test_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |f| f.adapter :test, stubs }
  end

  # Crea una strategia con `find_first_listing_url` pre-impostato
  # per testare solo l'estrazione email senza dipendere dal parsing della ricerca
  def strategy_with_direct_detail(client, url)
    strategy = Discovery::Strategies::PagineGialleStrategy.new(
      company: @company, http_client: client
    )
    strategy.define_singleton_method(:find_first_listing_url) { |_| url }
    strategy
  end
end
