# app/services/discovery/google_places_service.rb
#
# Fase 1 — Discovery Service
# Usa Places API (New) — https://places.googleapis.com/v1/
#
# Responsabilità:
#   - Chiama Google Places Text Search (New) per trovare attività nella zona
#   - Suddivide automaticamente l'area in sub-zone (griglia esagonale)
#     per superare il limite di 60 risultati per singola query
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

    # Field mask per Text Search — IDs + nextPageToken per paginazione
    TEXT_SEARCH_FIELD_MASK = "places.id,nextPageToken"

    # Field mask per Place Details — tutti i campi necessari
    PLACE_DETAILS_FIELD_MASK = %w[
      id displayName formattedAddress nationalPhoneNumber
      websiteUri rating userRatingCount photos
      addressComponents types businessStatus
    ].join(",")

    # Sub-raggio massimo per ogni zona della griglia (metri).
    # Con 5000m e 3 pagine da 20, ogni zona può trovare fino a 60 risultati.
    SUB_ZONE_RADIUS = 5_000

    # Limite massimo di sub-zone per contenere i costi API.
    # 19 zone × 60 risultati = fino a ~1140 candidati (~300-400 unici).
    MAX_ZONES = 19

    Result = Struct.new(:companies, :errors, :skipped_count, :total_found, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    # Supporta due modalità:
    #   1. category: (classica) — usa CATEGORY_QUERY_MAP per costruire la query
    #   2. query: (libera)      — query Maps diretta (es. "medici di base Roma")
    # campaign_id:    associa le company trovate alla Campaign
    # skip_websites:  true (default) = salta aziende con sito web (Web Agency)
    #                 false          = include tutti (Outreach — medici, tabaccai, etc.)
    def initialize(category: nil, query: nil, location:, radius: 15_000, campaign_id: nil, skip_websites: true, http_client: nil)
      @category      = category
      @free_query    = query
      @campaign_id   = campaign_id
      @skip_websites = skip_websites
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
      Rails.logger.info "[GooglePlacesService] Ricerca: #{search_text} — location=#{@location} radius=#{@radius}"

      place_ids = fetch_place_ids_with_grid
      Rails.logger.info "[GooglePlacesService] Place IDs unici trovati: #{place_ids.size}"

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

    # ─── Griglia geografica ───────────────────────────────────────────────────

    # Geocoda la location testuale in coordinate lat/lng via Places Text Search
    def geocode_location
      body = { textQuery: @location, languageCode: "it", maxResultCount: 1 }
      response = @client.post("/v1/places:searchText") do |req|
        req.headers["Content-Type"]     = "application/json"
        req.headers["X-Goog-Api-Key"]   = @api_key
        req.headers["X-Goog-FieldMask"] = "places.location"
        req.body = body.to_json
      end

      return nil unless response.status == 200

      data  = JSON.parse(response.body)
      place = data.dig("places", 0, "location")
      return nil unless place

      { lat: place["latitude"], lng: place["longitude"] }
    rescue => e
      Rails.logger.warn "[GooglePlacesService] Geocoding fallito: #{e.message}"
      nil
    end

    # Genera punti della griglia esagonale che copre il cerchio richiesto.
    # Restituisce array di { lat:, lng:, radius: } per ogni sub-zona.
    def generate_grid_zones(center, radius)
      # Se il raggio è piccolo, basta una zona singola
      if radius <= SUB_ZONE_RADIUS
        return [ { lat: center[:lat], lng: center[:lng], radius: radius } ]
      end

      sub_r = SUB_ZONE_RADIUS
      zones = []

      # Centro
      zones << { lat: center[:lat], lng: center[:lng], radius: sub_r }

      # Anelli concentrici con pattern esagonale
      # Distanza tra centri: 1.5 * sub_r (overlap ~25% per non perdere risultati ai bordi)
      step = sub_r * 1.5
      ring = 1

      while step * ring < radius + sub_r
        dist = step * ring
        # Punti sull'anello: 6 * ring (pattern esagonale)
        n_points = 6 * ring
        n_points.times do |i|
          angle = (2 * Math::PI * i) / n_points
          dlat = dist / 111_320.0 # ~111.32 km per grado di latitudine
          dlng = dist / (111_320.0 * Math.cos(center[:lat] * Math::PI / 180.0))
          zones << {
            lat: center[:lat] + dlat * Math.cos(angle),
            lng: center[:lng] + dlng * Math.sin(angle),
            radius: sub_r
          }
        end
        ring += 1
      end

      # Limita il numero di zone per contenere i costi API
      if zones.size > MAX_ZONES
        Rails.logger.info "[GooglePlacesService] Griglia troncata: #{zones.size} → #{MAX_ZONES} zone (raggio troppo ampio)"
        zones = zones.first(MAX_ZONES)
      end

      zones
    end

    # Ricerca con griglia: geocoda, genera sub-zone, lancia Text Search per ognuna
    def fetch_place_ids_with_grid
      center = geocode_location

      # Fallback: se il geocoding fallisce, usa la ricerca classica senza locationBias
      if center.nil?
        Rails.logger.warn "[GooglePlacesService] Geocoding fallito, ricerca senza griglia"
        return fetch_place_ids_for_zone(nil)
      end

      zones = generate_grid_zones(center, @radius)
      Rails.logger.info "[GooglePlacesService] Griglia: #{zones.size} sub-zone (raggio=#{@radius}m, sub=#{SUB_ZONE_RADIUS}m)"

      all_place_ids = []

      zones.each_with_index do |zone, idx|
        Rails.logger.debug "[GooglePlacesService] Sub-zona #{idx + 1}/#{zones.size}: " \
                           "lat=#{zone[:lat].round(4)} lng=#{zone[:lng].round(4)} r=#{zone[:radius]}"

        ids = fetch_place_ids_for_zone(zone)
        new_ids = ids - all_place_ids
        all_place_ids.concat(new_ids)

        Rails.logger.debug "[GooglePlacesService] Sub-zona #{idx + 1}: #{ids.size} trovati, #{new_ids.size} nuovi (totale: #{all_place_ids.size})"

        # Piccola pausa tra sub-zone per non sovraccaricare la API
        sleep(0.5) if idx < zones.size - 1
      end

      all_place_ids
    end

    # ─── Ricerca e paginazione per singola zona ──────────────────────────────

    def fetch_place_ids_for_zone(zone)
      place_ids       = []
      next_page_token = nil

      loop do
        data = text_search_page(next_page_token, zone)
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

    def text_search_page(page_token = nil, zone = nil)
      body = {
        textQuery:      zone ? search_text : search_query_with_location,
        languageCode:   "it",
        maxResultCount: 20
      }
      body[:pageToken] = page_token if page_token.present?

      # Se abbiamo coordinate, usiamo locationBias per circoscrivere la ricerca
      if zone
        body[:locationBias] = {
          circle: {
            center: { latitude: zone[:lat], longitude: zone[:lng] },
            radius: zone[:radius].to_f
          }
        }
      end

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

      # Salta se l'azienda ha già un sito web (solo in modalità Web Agency)
      if @skip_websites && details["websiteUri"].present?
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
        has_website:        details["websiteUri"].present?,
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

    # Testo di ricerca senza location (usato con locationBias)
    def search_text
      if @free_query.present?
        @free_query
      else
        CATEGORY_QUERY_MAP.fetch(@category, @category.to_s)
      end
    end

    # Testo di ricerca con location (fallback senza geocoding)
    def search_query_with_location
      "#{search_text} #{@location}"
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
