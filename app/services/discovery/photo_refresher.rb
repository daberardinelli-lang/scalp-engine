# app/services/discovery/photo_refresher.rb
#
# Ri-scarica gli URL delle foto Google Maps di una Company dai Place Details
# (New) e aggiorna `maps_photo_urls`. Serve perché i photo resource name di
# Google scadono nel tempo (il media endpoint inizia a rispondere 400/404):
# rinfrescando gli URL prima del build, PhotoDownloader può salvare le foto in
# locale (copie permanenti).
#
# Uso:
#   Discovery::PhotoRefresher.call(company: company)  # => Result
#
module Discovery
  class PhotoRefresher
    PLACES_BASE_URL = "https://places.googleapis.com"
    FIELD_MASK      = "photos"
    MAX_PHOTOS      = 5

    Result = Struct.new(:photo_urls, :refreshed, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(company:, http_client: nil)
      @company = company
      @api_key = ENV.fetch("GOOGLE_PLACES_API_KEY") { raise "GOOGLE_PLACES_API_KEY non configurata" }
      @client  = http_client || build_client
    end

    def call
      if @company.google_place_id.blank?
        return Result.new(photo_urls: existing, refreshed: false, error: "place_id mancante")
      end

      response = @client.get("/v1/places/#{@company.google_place_id}") do |req|
        req.headers["X-Goog-Api-Key"]   = @api_key
        req.headers["X-Goog-FieldMask"] = FIELD_MASK
        req.params["languageCode"]      = "it"
      end

      unless response.status == 200
        msg = (JSON.parse(response.body).dig("error", "message") rescue nil) || response.status.to_s
        return Result.new(photo_urls: existing, refreshed: false, error: "Place Details #{response.status}: #{msg}")
      end

      urls = build_photo_urls(JSON.parse(response.body)["photos"])

      # Non sovrascrivere con vuoto (fetch transitorio senza foto)
      @company.update_column(:maps_photo_urls, urls) if urls.present?

      Result.new(photo_urls: urls, refreshed: urls.present?, error: nil)
    rescue Faraday::Error => e
      Result.new(photo_urls: existing, refreshed: false, error: "HTTP error: #{e.message}")
    rescue JSON::ParserError => e
      Result.new(photo_urls: existing, refreshed: false, error: "JSON error: #{e.message}")
    end

    private

    def existing
      Array(@company.maps_photo_urls)
    end

    # Stesso formato usato da Discovery::GooglePlacesService#build_photo_urls
    def build_photo_urls(photos)
      return [] if photos.blank?

      photos.first(MAX_PHOTOS).filter_map do |photo|
        name = photo["name"]
        next if name.blank?

        "#{PLACES_BASE_URL}/v1/#{name}/media?maxWidthPx=800&key=#{@api_key}"
      end
    end

    def build_client
      Faraday.new(url: PLACES_BASE_URL) do |f|
        f.request :retry,
                  max:        2,
                  interval:   1.0,
                  exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        f.options.timeout      = 15
        f.options.open_timeout = 5
      end
    end
  end
end
