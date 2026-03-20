# app/services/discovery/google_places_service.rb
#
# Fase 1 — Discovery Service
#
# Responsabilità:
#   - Chiama Google Places Text Search API per trovare attività nella zona
#   - Per ogni risultato, chiama Place Details per verificare presenza del sito web
#   - Filtra le aziende che non hanno sito web
#   - Persiste/aggiorna Company records con status "discovered"
#   - Gestisce paginazione (fino a 60 risultati, 3 pagine da 20)
#
# Uso:
#   result = Discovery::GooglePlacesService.call(
#     category: "restaurant",
#     location: "Prato, Italia",
#     radius:   15_000
#   )
#   result.companies      # => Array<Company> — aziende senza sito salvate
#   result.errors         # => Array<String>  — errori non bloccanti
#   result.skipped_count  # => Integer        — aziende con sito web (scartate)
#   result.total_found    # => Integer        — totale risultati API prima del filtro

module Discovery
  class GooglePlacesService
    PLACES_BASE_URL = "https://maps.googleapis.com"

    # Traduzione categoria interna → termine di ricerca in italiano
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

    # Mapping Google Places types → categorie Company
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

    Result = Struct.new(:companies, :errors, :skipped_count, :total_found, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(category:, location:, radius: 15_000, http_client: nil)
      @category      = category
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
      place_ids      = []
      next_page_token = nil

      loop do
        data = text_search_page(next_page_token)
        break if data.nil?

        results = data["results"] || []
        @total_found += results.size
        place_ids.concat(results.map { |r| r["place_id"] }.compact)

        next_page_token = data["next_page_token"]
        break if next_page_token.nil?

        # Google richiede un breve delay prima di usare il next_page_token
        sleep(2)
      end

      place_ids.uniq
    rescue => e
      @errors << "Text Search fallita: #{e.message}"
      []
    end

    def text_search_page(page_token = nil)
      params = {
        query:    search_query,
        key:      @api_key,
        language: "it"
      }
      params[:pagetoken] = page_token if page_token.present?

      response = @client.get("/maps/api/place/textsearch/json", params)
      data     = JSON.parse(response.body)

      case data["status"]
      when "OK"
        data
      when "ZERO_RESULTS"
        Rails.logger.info "[GooglePlacesService] Nessun risultato per: #{search_query}"
        nil
      else
        @errors << "Places API error: #{data['status']} — #{data['error_message']}"
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
      if details["website"].present?
        @skipped_count += 1
        Rails.logger.debug "[GooglePlacesService] Saltata (ha sito): #{details['name']}"
        return
      end

      # Salta se l'azienda è permanentemente chiusa
      if details["business_status"] == "CLOSED_PERMANENTLY"
        @skipped_count += 1
        Rails.logger.debug "[GooglePlacesService] Saltata (chiusa definitivamente): #{details['name']}"
        return
      end

      company = upsert_company(details)
      @companies << company if company
    rescue => e
      @errors << "Errore elaborazione place_id=#{place_id}: #{e.message}"
    end

    def fetch_place_details(place_id)
      fields = %w[
        place_id name formatted_address formatted_phone_number
        website rating user_ratings_total photos
        address_components types business_status
      ].join(",")

      response = @client.get("/maps/api/place/details/json", {
        place_id: place_id,
        fields:   fields,
        key:      @api_key,
        language: "it"
      })

      data = JSON.parse(response.body)

      unless data["status"] == "OK"
        @errors << "Place Details error per #{place_id}: #{data['status']}"
        return nil
      end

      data["result"]
    rescue Faraday::Error => e
      @errors << "HTTP error Place Details #{place_id}: #{e.message}"
      nil
    rescue JSON::ParserError => e
      @errors << "JSON parsing error Place Details #{place_id}: #{e.message}"
      nil
    end

    # ─── Persistenza ─────────────────────────────────────────────────────────

    def upsert_company(details)
      components = details["address_components"] || []
      city       = extract_component(components, "locality") ||
                   extract_component(components, "administrative_area_level_3")
      province   = extract_component(components, "administrative_area_level_2")
      route      = extract_component(components, "route")
      number     = extract_component(components, "street_number")
      address    = [ route, number ].compact.join(", ").presence

      photo_urls = build_photo_urls(details["photos"])
      category   = normalize_category(details["types"])

      company = Company.find_or_initialize_by(google_place_id: details["place_id"])

      # Non sovrascrivere aziende già avanzate nella pipeline
      return company unless company.new_record? || company.status == "discovered"

      company.assign_attributes(
        name:               details["name"],
        category:           category,
        address:            address,
        city:               city,
        province:           province,
        phone:              details["formatted_phone_number"],
        maps_rating:        details["rating"],
        maps_reviews_count: details["user_ratings_total"] || 0,
        has_website:        false,
        maps_photo_urls:    photo_urls,
        status:             "discovered"
      )

      if company.save
        company
      else
        @errors << "Validazione fallita per #{details['name']}: #{company.errors.full_messages.join(', ')}"
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
      comp = components.find { |c| Array(c["types"]).include?(type) }
      comp&.dig("short_name")
    end

    def build_photo_urls(photos)
      return [] if photos.blank?

      photos.first(5).filter_map do |photo|
        ref = photo["photo_reference"]
        next if ref.blank?

        "https://maps.googleapis.com/maps/api/place/photo" \
          "?maxwidth=800&photoreference=#{ref}&key=#{@api_key}"
      end
    end

    def search_query
      term = CATEGORY_QUERY_MAP.fetch(@category, @category)
      "#{term} #{@location}"
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
