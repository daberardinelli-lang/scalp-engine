require "test_helper"

class Discovery::PhotoRefresherTest < ActiveSupport::TestCase
  setup do
    @company = FactoryBot.create(:company,
                                 name:            "Bar del Test",
                                 status:          "enriched",
                                 google_place_id: "PLACE_123",
                                 maps_photo_urls: ["https://places.googleapis.com/v1/places/PLACE_123/photos/OLD/media?key=k"])
  end

  test "rinfresca maps_photo_urls con gli URL freschi dai Place Details" do
    body = JSON.generate("photos" => [
      { "name" => "places/PLACE_123/photos/AAA" },
      { "name" => "places/PLACE_123/photos/BBB" }
    ])
    client = build_test_client { |stub| stub.get("/v1/places/PLACE_123") { [200, {}, body] } }

    result = Discovery::PhotoRefresher.call(company: @company, http_client: client)

    assert result.success?, result.error
    assert result.refreshed
    assert_equal 2, result.photo_urls.size
    assert result.photo_urls.first.include?("places/PLACE_123/photos/AAA/media")
    assert_equal result.photo_urls, @company.reload.maps_photo_urls
    refute @company.maps_photo_urls.first.include?("/OLD/"), "URL vecchio sostituito"
  end

  test "non sovrascrive con vuoto se i Place Details non hanno foto" do
    client = build_test_client { |stub| stub.get("/v1/places/PLACE_123") { [200, {}, JSON.generate({})] } }

    result = Discovery::PhotoRefresher.call(company: @company, http_client: client)

    refute result.refreshed
    assert @company.reload.maps_photo_urls.first.include?("/OLD/"), "vecchi URL conservati"
  end

  test "ritorna errore (senza crash) se Place Details risponde non-200" do
    err = JSON.generate("error" => { "message" => "denied" })
    client = build_test_client { |stub| stub.get("/v1/places/PLACE_123") { [403, {}, err] } }

    result = Discovery::PhotoRefresher.call(company: @company, http_client: client)

    refute result.success?
    assert result.error.include?("403")
  end

  test "ritorna errore se la company non ha google_place_id" do
    @company.update_column(:google_place_id, nil)
    result = Discovery::PhotoRefresher.call(company: @company, http_client: build_test_client { |s| })

    refute result.success?
    assert result.error.include?("place_id")
  end

  private

  def build_test_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new(url: "https://places.googleapis.com") { |f| f.adapter :test, stubs }
  end
end
