# app/services/discovery/review_fetcher_service.rb
#
# Recupera le recensioni pubbliche di un'azienda tramite Places API (New)
# (campo `reviews` — fino a 5 recensioni, include testo, rating, autore, data).
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
    PLACES_BASE_URL = "https://places.googleapis.com"

    Result = Struct.new(:reviews, :error, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(google_place_id:, http_client: nil)
      @place_id = google_place_id
      @api_key  = ENV.fetch("GOOGLE_PLACES_API_KEY") { raise "GOOGLE_PLACES_API_KEY non configurata" }
      @client   = http_client || build_client
    end

    def call
      response = @client.get("/v1/places/#{@place_id}") do |req|
        req.headers["X-Goog-Api-Key"]   = @api_key
        req.headers["X-Goog-FieldMask"] = "reviews"
        req.params["languageCode"]       = "it"
        req.params["reviewsSort"]        = "NEWEST"
      end

      unless response.status == 200
        data = JSON.parse(response.body) rescue {}
        msg  = data.dig("error", "message") || response.status.to_s
        return Result.new(reviews: [], error: "Places API error: #{msg}")
      end

      data        = JSON.parse(response.body)
      raw_reviews = data["reviews"] || []
      reviews     = raw_reviews.map { |r| parse_review(r) }.compact

      Result.new(reviews: reviews, error: nil)
    rescue Faraday::Error => e
      Result.new(reviews: [], error: "HTTP error: #{e.message}")
    rescue JSON::ParserError => e
      Result.new(reviews: [], error: "JSON parse error: #{e.message}")
    end

    private

    def parse_review(raw)
      # Places API (New) struttura:
      # raw["text"]["text"], raw["rating"], raw["authorAttribution"]["displayName"], raw["publishTime"]
      text = raw.dig("text", "text").to_s.strip
      return nil if text.blank?

      publish_time = raw["publishTime"]
      date = begin
        Time.parse(publish_time).strftime("%Y-%m-%d")
      rescue
        Time.now.strftime("%Y-%m-%d")
      end

      {
        "author" => raw.dig("authorAttribution", "displayName").to_s.strip,
        "rating" => raw["rating"].to_i,
        "text"   => text.truncate(500),
        "date"   => date
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
