# app/services/discovery/google_places_service.rb
#
# Fase 1 — Discovery Service
# Usa Places API (New) — https://places.googleapis.com/v1/
#
# Responsabilità:
#   - Chiama Google Places Text Search (New) per trovare attività nella zona
#   - Per ogni risultato, chiama Place Details (New) per verificare presenza sito web
#   - Filtra le aziende che non hanno sito web
#   - Persiste/aggiorna Company records con status "discovered"
#
# Uso:
#   result = Discovery::GooglePlacesService.call(
#     category: "restaurant",
#     location: "Prato, Italia",
#     radius:   15_000
#   )

module Discovery
  class GooglePlacesService
    PLACES_BASE_URL = "https://places.googleapis.com"

    CATEGORY_QUERY_MAP = {
      "restaurant"  => "ristoranti",
      "bar"         => "bar",
      "pizzeria"    => "pizzerie",
      "plumber"     => "idraulici",
      "electrician" => "elettricisti",
      "builder"     => "imprese edili",
      "retail"      => "negozi",
      "shop"        => "negozi",
      "lawyer"      => "avvocati",
      "accountant"  => "commercialisti",
      "notary"      => "notai",
      "other"       => "attività commerciali"
    }.freeze

    GOOGLE_TYPE_MAP = {
      "restaurant"          => "restaurant",
      "food"                => "restaurant",
      "meal_delivery"       => "restaurant",
      "meal_takeaway"       => "restaurant",
      "bar"                 => "bar",
      "night_club"          => "bar",
      "cafe"                => "bar",
      "plumber"             => "plumber",
      "electrician"         => "electrician",
      "general_contractor"  => "builder",
      "roofing_contractor"  => "builder",
      "store"               => "retail",
      "clothing_store"      => "retail",
      "shoe_store"          => "retail",
      "home_goods_store"    => "retail",
      "furniture_store"     => "retail",
      "electronics_store"   => "retail",
      "lawyer"              => "lawyer",
      "legal_services"      => "lawyer",
      "accounting"          => "accountant",
      "finance"             => "accountant",
      "notary"              => "notary"
    }.freeze

    # Field mask per Text Search — solo IDs per minimizzare costi API
    TEXT_SEARCH_FIELD_MASK = "places.id"

    # Field mask per Place Details — tutti i campi necessari
    PLACE_DETAILS_FIELD_MASK = %w[
      id displayName formattedAddress nationalPhoneNumber
      websiteUri rating userRatingCount photos
      addressComponents types businessStatus
    ].join(",")

    Result = Struct.new(:companies, :errors, :skipped_count, :total_found, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    # Supporta due modalità:
    #   1. category: (classica) — usa CATEGORY_QUERY_MAP per costruire la query
    #   2. query: (libera)      — query Maps diretta (es. "medici di base Roma")
    # campaign_id: associa le company trovate alla Campaign
    def initialize(category: nil, query: nil, location:, radius: 15_000, campaign_id: nil, http_client: nil)
      @category      = category
      @free_query    = query
      @campaign_id   = campaign_id
      @location      = location
      @radius        = radius
      @api_key       = ENV.fetch("GOOGLE_PLACES_API_KEY") { raise "GOOGLE_PLACES_API_KEY non configurata" }
      @client        = http_client || build_client
      @companies     = []
      @errors        = []
      @skipped_count = 0
      @total_found   = 0
    end

    def call
      Rails.logger.info "[GooglePlacesService] Ricerca: #{search_query}"

      place_ids = fetch_all_place_ids
      Rails.logger.info "[GooglePlacesService] Place IDs trovati: #{place_ids.size}"

      place_ids.each_with_index do |place_id, idx|
        Rails.logger.debug "[GooglePlacesService] Elaborazione #{idx + 1}/#{place_ids.size}: #{place_id}"
        process_place(place_id)
      end

      Rails.logger.info "[GooglePlacesService] Completato — salvate=#{@companies.size} " \
                        "scartate_con_sito=#{@skipped_count} errori=#{@errors.size}"

      Result.new(
        companies:     @companies,
        errors:        @errors,
        skipped_count: @skipped_count,
        total_found:   @total_found
      )
    end

    private

    # ─── Ricerca e paginazione ────────────────────────────────────────────────

    def fetch_all_place_ids
      place_ids       = []
      next_page_token = nil

      loop do
        data = text_search_page(next_page_token)
        break if data.nil?

        places = data["places"] || []
        @total_found += places.size
        place_ids.concat(places.map { |p| p["id"] }.compact)

        next_page_token = data["nextPageToken"]
        break if next_page_token.nil?

        # Places API (New) richiede breve delay prima di usare nextPageToken
        sleep(2)
      end

      place_ids.uniq
    rescue => e
      @errors << "Text Search fallita: #{e.message}"
      []
    end

    def text_search_page(page_token = nil)
      body = {
        textQuery:      search_query,
        languageCode:   "it",
        maxResultCount: 20
      }
      body[:pageToken] = page_token if page_token.present?

      response = @client.post("/v1/places:searchText") do |req|
        req.headers["Content-Type"]     = "application/json"
        req.headers["X-Goog-Api-Key"]   = @api_key
        req.headers["X-Goog-FieldMask"] = TEXT_SEARCH_FIELD_MASK
        req.body = body.to_json
      end

      if response.status == 200
        JSON.parse(response.body)
      else
        data = JSON.parse(response.body) rescue {}
        msg  = data.dig("error", "message") || response.status.to_s
        @errors << "Places API error: #{response.status} — #{msg}"
        nil
      end
    rescue Faraday::Error => e
      @errors << "HTTP error Text Search: #{e.message}"
      nil
    rescue JSON::ParserError => e
      @errors << "JSON parsing error Text Search: #{e.message}"
      nil
    end

    # ─── Dettaglio singolo posto ──────────────────────────────────────────────

    def process_place(place_id)
      details = fetch_place_details(place_id)
      return unless details

      # Salta se l'azienda ha già un sito web
      if details["websiteUri"].present?
        @skipped_count += 1
        Rails.logger.debug "[GooglePlacesService] Saltata (ha sito): #{details.dig('displayName', 'text')}"
        return
      end

      # Salta se l'azienda è permanentemente chiusa
      if details["businessStatus"] == "CLOSED_PERMANENTLY"
        @skipped_count += 1
        Rails.logger.debug "[GooglePlacesService] Saltata (chiusa definitivamente): #{details.dig('displayName', 'text')}"
        return
      end

      company = upsert_company(details)
      @companies << company if company
    rescue => e
      @errors << "Errore elaborazione place_id=#{place_id}: #{e.message}"
    end

    def fetch_place_details(place_id)
      response = @client.get("/v1/places/#{place_id}") do |req|
        req.headers["X-Goog-Api-Key"]   = @api_key
        req.headers["X-Goog-FieldMask"] = PLACE_DETAILS_FIELD_MASK
        req.params["languageCode"]       = "it"
      end

      if response.status == 200
        JSON.parse(response.body)
      else
        data = JSON.parse(response.body) rescue {}
        msg  = data.dig("error", "message") || response.status.to_s
        @errors << "Place Details error per #{place_id}: #{msg}"
        nil
      end
    rescue Faraday::Error => e
      @errors << "HTTP error Place Details #{place_id}: #{e.message}"
      nil
    rescue JSON::ParserError => e
      @errors << "JSON parsing error Place Details #{place_id}: #{e.message}"
      nil
    end

    # ─── Persistenza ─────────────────────────────────────────────────────────

    def upsert_company(details)
      components = details["addressComponents"] || []
      city       = extract_component(components, "locality") ||
                   extract_component(components, "administrative_area_level_3")
      province   = extract_component(components, "administrative_area_level_2")
      route      = extract_component(components, "route")
      number     = extract_component(components, "street_number")
      address    = [ route, number ].compact.join(", ").presence

      photo_urls = build_photo_urls(details["photos"])
      category   = normalize_category(details["types"])
      place_id   = details["id"]
      name       = details.dig("displayName", "text")

      company = Company.find_or_initialize_by(google_place_id: place_id)

      # Non sovrascrivere aziende già avanzate nella pipeline
      return company unless company.new_record? || company.status == "discovered"

      attrs = {
        name:               name,
        category:           category,
        address:            address,
        city:               city,
        province:           province,
        phone:              details["nationalPhoneNumber"],
        maps_rating:        details["rating"],
        maps_reviews_count: details["userRatingCount"] || 0,
        has_website:        false,
        maps_photo_urls:    photo_urls,
        status:             "discovered"
      }
      attrs[:campaign_id] = @campaign_id if @campaign_id.present?

      company.assign_attributes(attrs)

      if company.save
        company
      else
        @errors << "Validazione fallita per #{name}: #{company.errors.full_messages.join(', ')}"
        nil
      end
    end

    # ─── Helpers ─────────────────────────────────────────────────────────────

    def normalize_category(types)
      return "other" if types.blank?

      types.each do |type|
        mapped = GOOGLE_TYPE_MAP[type]
        return mapped if mapped && Company::CATEGORIES.include?(mapped)
      end

      "other"
    end

    def extract_component(components, type)
      # Places API (New) usa shortText invece di short_name
      comp = components.find { |c| Array(c["types"]).include?(type) }
      comp&.dig("shortText")
    end

    def build_photo_urls(photos)
      return [] if photos.blank?

      photos.first(5).filter_map do |photo|
        # Places API (New): photo["name"] è il resource name, es: "places/xxx/photos/yyy"
        photo_name = photo["name"]
        next if photo_name.blank?

        "https://places.googleapis.com/v1/#{photo_name}/media?maxWidthPx=800&key=#{@api_key}"
      end
    end

    def search_query
      if @free_query.present?
        "#{@free_query} #{@location}"
      else
        term = CATEGORY_QUERY_MAP.fetch(@category, @category.to_s)
        "#{term} #{@location}"
      end
    end

    def build_client
      Faraday.new(url: PLACES_BASE_URL) do |f|
        f.request :retry,
                  max:        3,
                  interval:   1.0,
                  exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        f.options.timeout      = 15
        f.options.open_timeout = 5
      end
    end
  end
end
