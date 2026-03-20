# app/services/discovery/review_fetcher_service.rb
#
# Recupera le recensioni pubbliche di un'azienda tramite Google Places Details API
# (campo `reviews` — fino a 5 recensioni, include testo, rating, autore, data).
#
# Non usa browser headless: è una pura chiamata API, rapida e affidabile.
# Le recensioni vengono usate in Fase 3 da Claude AI per generare contenuti
# personalizzati (es. "I nostri clienti dicono: ...").
#
# Uso:
#   result = Discovery::ReviewFetcherService.call(
#     google_place_id: "ChIJ...",
#     http_client:     nil   # opzionale, per test
#   )
#   result.reviews   # => [{author:, rating:, text:, date:}, ...]
#   result.error     # => String | nil

module Discovery
  class ReviewFetcherService
    PLACES_BASE_URL = "https://maps.googleapis.com"

    Result = Struct.new(:reviews, :error, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(google_place_id:, http_client: nil)
      @place_id  = google_place_id
      @api_key   = ENV.fetch("GOOGLE_PLACES_API_KEY") { raise "GOOGLE_PLACES_API_KEY non configurata" }
      @client    = http_client || build_client
    end

    def call
      response = @client.get("/maps/api/place/details/json", {
        place_id: @place_id,
        fields:   "reviews",
        key:      @api_key,
        language: "it",
        reviews_sort: "newest"
      })

      data = JSON.parse(response.body)

      unless data["status"] == "OK"
        return Result.new(reviews: [], error: "Places API error: #{data['status']}")
      end

      raw_reviews = data.dig("result", "reviews") || []
      reviews     = raw_reviews.map { |r| parse_review(r) }.compact

      Result.new(reviews: reviews, error: nil)
    rescue Faraday::Error => e
      Result.new(reviews: [], error: "HTTP error: #{e.message}")
    rescue JSON::ParserError => e
      Result.new(reviews: [], error: "JSON parse error: #{e.message}")
    end

    private

    def parse_review(raw)
      text = raw["text"].to_s.strip
      return nil if text.blank?

      {
        "author" => raw["author_name"].to_s.strip,
        "rating" => raw["rating"].to_i,
        "text"   => text.truncate(500),
        "date"   => Time.at(raw["time"].to_i).strftime("%Y-%m-%d")
      }
    end

    def build_client
      Faraday.new(url: PLACES_BASE_URL) do |f|
        f.request :retry, max: 2, interval: 1.0,
                  exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        f.options.timeout = 10
      end
    end
  end
end
