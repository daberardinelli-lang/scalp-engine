require "test_helper"

class Discovery::GooglePlacesServiceTest < ActiveSupport::TestCase
  # ─── Payload API di esempio ───────────────────────────────────────────────

  TEXT_SEARCH_RESPONSE = JSON.generate(
    "status"  => "OK",
    "results" => [
      { "place_id" => "PLACE_NO_SITE" },
      { "place_id" => "PLACE_WITH_SITE" },
      { "place_id" => "PLACE_CLOSED" }
    ]
  )

  TEXT_SEARCH_EMPTY = JSON.generate("status" => "ZERO_RESULTS", "results" => [])
  TEXT_SEARCH_ERROR = JSON.generate("status" => "REQUEST_DENIED", "error_message" => "API key non valida")

  DETAILS_NO_SITE = JSON.generate(
    "status" => "OK",
    "result" => {
      "place_id"               => "PLACE_NO_SITE",
      "name"                   => "Ristorante Bella Italia",
      "formatted_phone_number" => "0574 123456",
      "website"                => nil,
      "rating"                 => 4.2,
      "user_ratings_total"     => 87,
      "business_status"        => "OPERATIONAL",
      "types"                  => ["restaurant", "food"],
      "photos"                 => [{ "photo_reference" => "ref_abc", "height" => 600, "width" => 800 }],
      "address_components"     => [
        { "types" => ["route"],                        "short_name" => "Via Roma" },
        { "types" => ["street_number"],               "short_name" => "1" },
        { "types" => ["locality"],                     "short_name" => "Prato" },
        { "types" => ["administrative_area_level_2"], "short_name" => "PO" }
      ]
    }
  )

  DETAILS_WITH_SITE = JSON.generate(
    "status" => "OK",
    "result" => {
      "place_id" => "PLACE_WITH_SITE", "name" => "Bar Con Sito",
      "website"  => "https://esempio.it", "business_status" => "OPERATIONAL",
      "types"    => ["bar"], "address_components" => []
    }
  )

  DETAILS_CLOSED = JSON.generate(
    "status" => "OK",
    "result" => {
      "place_id" => "PLACE_CLOSED", "name" => "Trattoria Chiusa",
      "website"  => nil, "business_status" => "CLOSED_PERMANENTLY",
      "types"    => ["restaurant"], "address_components" => []
    }
  )

  # ─── Helpers ──────────────────────────────────────────────────────────────

  setup do
    ENV["GOOGLE_PLACES_API_KEY"] = "TEST_KEY"
  end

  # Costruisce un Faraday client con adapter di test
  def build_test_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new(url: "https://maps.googleapis.com") do |f|
      f.adapter :test, stubs
    end
  end

  # Chiama il service con un client HTTP controllato
  def run_service(client:, category: "restaurant", location: "Prato, Italia", radius: 15_000)
    Discovery::GooglePlacesService.call(
      category:    category,
      location:    location,
      radius:      radius,
      http_client: client
    )
  end

  # ─── Test: flusso principale ──────────────────────────────────────────────

  test "salva le aziende senza sito, scarta quelle con sito e quelle chiuse" do
    client = build_test_client do |stub|
      stub.get("/maps/api/place/textsearch/json") { [200, {}, TEXT_SEARCH_RESPONSE] }
      stub.get("/maps/api/place/details/json") do |env|
        place_id = Rack::Utils.parse_query(env.url.query)["place_id"]
        body = case place_id
               when "PLACE_NO_SITE"   then DETAILS_NO_SITE
               when "PLACE_WITH_SITE" then DETAILS_WITH_SITE
               when "PLACE_CLOSED"    then DETAILS_CLOSED
               end
        [200, {}, body]
      end
    end

    assert_difference "Company.count", 1 do
      result = run_service(client: client)

      assert_equal 1, result.companies.size,     "solo 1 azienda salvata (senza sito + operativa)"
      assert_equal 2, result.skipped_count,      "2 scartate (con sito + chiusa)"
      assert_equal 3, result.total_found,        "3 risultati totali dall'API"
      assert_empty result.errors
    end

    company = Company.find_by!(google_place_id: "PLACE_NO_SITE")
    assert_equal "Ristorante Bella Italia", company.name
    assert_equal "restaurant",             company.category
    assert_equal "Prato",                  company.city
    assert_equal "PO",                     company.province
    assert_equal "Via Roma, 1",            company.address
    assert_equal "0574 123456",            company.phone
    assert_in_delta 4.2, company.maps_rating.to_f, 0.01
    assert_equal 87,          company.maps_reviews_count
    assert_equal false,       company.has_website
    assert_equal "discovered", company.status
    assert_equal 1,            company.maps_photo_urls.size
    assert_match "ref_abc",    company.maps_photo_urls.first
  end

  test "non crea duplicati — aggiorna record esistente in stato discovered" do
    FactoryBot.create(:company, google_place_id: "PLACE_NO_SITE",
                                status: "discovered", name: "Vecchio Nome")

    client = build_test_client do |stub|
      stub.get("/maps/api/place/textsearch/json") { [200, {}, TEXT_SEARCH_RESPONSE] }
      stub.get("/maps/api/place/details/json") do |env|
        place_id = Rack::Utils.parse_query(env.url.query)["place_id"]
        body = case place_id
               when "PLACE_NO_SITE"   then DETAILS_NO_SITE
               when "PLACE_WITH_SITE" then DETAILS_WITH_SITE
               when "PLACE_CLOSED"    then DETAILS_CLOSED
               end
        [200, {}, body]
      end
    end

    assert_no_difference "Company.count" do
      result = run_service(client: client)
      assert_equal 1, result.companies.size
    end

    assert_equal "Ristorante Bella Italia", Company.find_by!(google_place_id: "PLACE_NO_SITE").name
  end

  test "non sovrascrive aziende già avanzate nella pipeline" do
    FactoryBot.create(:company, google_place_id: "PLACE_NO_SITE",
                                status: "enriched", name: "Nome Originale")

    client = build_test_client do |stub|
      stub.get("/maps/api/place/textsearch/json") { [200, {}, TEXT_SEARCH_RESPONSE] }
      stub.get("/maps/api/place/details/json") do |env|
        place_id = Rack::Utils.parse_query(env.url.query)["place_id"]
        body = case place_id
               when "PLACE_NO_SITE"   then DETAILS_NO_SITE
               when "PLACE_WITH_SITE" then DETAILS_WITH_SITE
               when "PLACE_CLOSED"    then DETAILS_CLOSED
               end
        [200, {}, body]
      end
    end

    run_service(client: client)

    company = Company.find_by!(google_place_id: "PLACE_NO_SITE")
    assert_equal "Nome Originale", company.name    # non sovrascritto
    assert_equal "enriched",       company.status  # non retrocesso a discovered
  end

  test "ZERO_RESULTS non causa errori" do
    client = build_test_client do |stub|
      stub.get("/maps/api/place/textsearch/json") { [200, {}, TEXT_SEARCH_EMPTY] }
    end

    result = run_service(client: client)

    assert_empty result.companies
    assert_empty result.errors
    assert_equal 0, result.total_found
  end

  test "errore API viene tracciato in result.errors" do
    client = build_test_client do |stub|
      stub.get("/maps/api/place/textsearch/json") { [200, {}, TEXT_SEARCH_ERROR] }
    end

    result = run_service(client: client)

    assert_empty result.companies
    assert_equal 1, result.errors.size
    assert_match "REQUEST_DENIED", result.errors.first
  end

  # ─── Test: normalize_category ────────────────────────────────────────────

  test "mappa tipi Google → categorie Company correttamente" do
    service = Discovery::GooglePlacesService.new(
      category: "restaurant", location: "Test", http_client: Faraday.new
    )

    {
      %w[restaurant food]         => "restaurant",
      %w[bar]                     => "bar",
      %w[plumber]                 => "plumber",
      %w[electrician]             => "electrician",
      %w[general_contractor]      => "builder",
      %w[store clothing_store]    => "retail",
      %w[lawyer legal_services]   => "lawyer",
      %w[accounting]              => "accountant",
      %w[notary]                  => "notary",
      %w[unknown_type]            => "other",
      []                          => "other",
      nil                         => "other"
    }.each do |types, expected|
      assert_equal expected, service.send(:normalize_category, types),
                   "#{types.inspect} → atteso '#{expected}'"
    end
  end

  # ─── Test: search_query ───────────────────────────────────────────────────

  test "search_query costruisce la query in italiano" do
    {
      "restaurant"  => "ristoranti Prato, Italia",
      "bar"         => "bar Prato, Italia",
      "pizzeria"    => "pizzerie Prato, Italia",
      "lawyer"      => "avvocati Prato, Italia",
      "accountant"  => "commercialisti Prato, Italia",
      "other"       => "attività commerciali Prato, Italia"
    }.each do |cat, expected_query|
      service = Discovery::GooglePlacesService.new(
        category: cat, location: "Prato, Italia", http_client: Faraday.new
      )
      assert_equal expected_query, service.send(:search_query)
    end
  end
end
