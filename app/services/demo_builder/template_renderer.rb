# app/services/demo_builder/template_renderer.rb
#
# Renderizza il template Liquid HTML a partire da un record Demo + Company.
# Restituisce la stringa HTML completa pronta per essere scritta su disco.
#
# Uso:
#   html = DemoBuilder::TemplateRenderer.render(demo: demo)
#
module DemoBuilder
  class TemplateRenderer
    TEMPLATE_PATH = Rails.root.join("app", "views", "demo_templates", "default.html.liquid").freeze

    Result = Struct.new(:html, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    # photo_paths: path locali delle foto già scaricate (es. ["img/photo_1.jpg"]).
    #   - nil  → fallback agli URL Google in maps_photo_urls (render diretto/legacy)
    #   - []   → nessuna foto (download fallito): galleria nascosta, niente URL Google
    def self.render(demo:, photo_paths: nil)
      new(demo: demo, photo_paths: photo_paths).render
    end

    def initialize(demo:, photo_paths: nil)
      @demo        = demo
      @company     = demo.company
      @photo_paths = photo_paths
    end

    def render
      template_source = File.read(TEMPLATE_PATH)
      liquid_template  = Liquid::Template.parse(template_source, error_mode: :strict)

      html = liquid_template.render(build_assigns, strict_variables: false)

      if liquid_template.errors.any?
        return Result.new(html: nil, errors: liquid_template.errors.map(&:message))
      end

      Result.new(html: html, errors: [])
    rescue Liquid::Error => e
      Result.new(html: nil, errors: ["Liquid error: #{e.message}"])
    rescue Errno::ENOENT => e
      Result.new(html: nil, errors: ["Template non trovato: #{e.message}"])
    rescue => e
      Result.new(html: nil, errors: ["TemplateRenderer error: #{e.message}"])
    end

    private

    # Trasforma la lista servizi (array di stringhe) in array di hash con icona SVG
    # pertinente, scelta dalle keyword del testo. Liquid accede a service.name /
    # service.icon. L'SVG NON viene escapato da Liquid → renderizzato inline.
    def services_with_icons
      @demo.services_detailed.map do |service|
        {
          "name" => service["name"].to_s,
          "icon" => DemoBuilder::ServiceIcons.icon_for(service["name"]),
          "desc" => service["desc"].to_s
        }
      end
    end

    # Sorgenti foto: path locali scaricati (preferiti) o URL Google (fallback legacy).
    # nil = non fornito → usa maps_photo_urls; [] = download fallito → nessuna foto.
    def photo_sources
      @photo_sources ||= @photo_paths.nil? ? Array(@company.maps_photo_urls) : @photo_paths
    end

    def build_assigns
      {
        # Azienda
        "company_name"       => @company.name.to_s,
        "city"               => @company.city.to_s,
        "province"           => @company.province.to_s,
        "address"            => @company.address.to_s,
        "phone"              => @company.phone.to_s,
        "phone_clean"        => clean_phone(@company.phone),
        "category_label"     => category_label,
        "google_maps_url"    => google_maps_url,
        "google_place_id"    => @company.google_place_id.to_s,

        # Valutazione
        "maps_rating"        => @company.maps_rating.to_s,
        "maps_reviews_count" => @company.maps_reviews_count.to_s,
        "rating_stars"       => build_stars(@company.maps_rating),

        # Contenuto AI
        "headline"           => @demo.generated_headline.to_s,
        "about"              => @demo.generated_about.to_s,
        "services"           => services_with_icons,
        "services_title"     => @demo.generated_services_title.to_s,
        "services_intro"     => @demo.generated_services_intro.to_s,
        "cta_text"           => @demo.generated_cta.to_s,

        # Foto (path locali scaricati al build, o URL Google in fallback):
        #   [0] hero a tutta pagina · [1] sezione "chi siamo" · [2..] galleria
        "hero_photo"         => (photo_sources[0] || "").to_s,
        "first_photo"        => (photo_sources[1] || "").to_s,
        "photos"             => (photo_sources[2..] || []),

        # Recensioni: solo quelle con testo e rating ≥ 4
        "reviews"            => best_reviews,

        # WhatsApp: link diretto con messaggio precomposto
        "whatsapp_url"       => build_whatsapp_url,

        # Mappa contatti: query per l'embed legacy (?output=embed), key-free —
        # evita la Maps Embed API e non espone la API key nell'HTML.
        "map_query"          => map_query,

        # Brand & meta
        "brand_name"         => ENV.fetch("BRAND_NAME", "WebRadar"),
        "brand_email"        => ENV.fetch("BRAND_EMAIL", "info@webradar.it"),
        "demo_base_domain"   => ENV.fetch("DEMO_BASE_DOMAIN", "demo.webradar.it"),
        "subdomain"          => @demo.subdomain.to_s,
        "generated_at"       => Time.current.strftime("%d/%m/%Y"),
        "privacy_url"        => "#{ENV.fetch('APP_BASE_URL', 'https://app.webradar.it')}/privacy"
      }
    end

    # Restituisce le migliori recensioni (testo presente, rating ≥ 4) come array di hash Liquid-safe
    def best_reviews
      return [] if @company.reviews_data.blank?

      @company.reviews_data
              .select { |r| r["text"].present? && r["rating"].to_i >= 4 }
              .sort_by { |r| -r["rating"].to_i }
              .first(3)
              .map do |r|
                {
                  "author" => r["author"].to_s,
                  "text"   => r["text"].to_s.truncate(260),
                  "stars"  => build_stars(r["rating"])
                }
              end
    end

    # "★★★★☆" da un rating numerico 0..5
    def build_stars(rating)
      return "" if rating.nil?

      full  = rating.to_f.floor.clamp(0, 5)
      empty = 5 - full
      ("★" * full) + ("☆" * empty)
    end

    # Etichetta categoria in italiano
    def category_label
      {
        "restaurant"    => "Ristorante",
        "artisan"       => "Artigiano",
        "shop"          => "Negozio",
        "professional"  => "Studio Professionale",
        "beauty"        => "Centro Estetico / Benessere",
        "accommodation" => "Struttura Ricettiva"
      }.fetch(@company.category.to_s, @company.category.to_s.humanize)
    end

    def google_maps_url
      return "" if @company.google_place_id.blank?

      "https://www.google.com/maps/place/?q=place_id:#{@company.google_place_id}"
    end

    # Query per l'embed mappa legacy (key-free): "Nome, indirizzo, città, prov."
    def map_query
      parts = [@company.name, @company.address, @company.city, @company.province].compact_blank
      ERB::Util.url_encode(parts.join(", "))
    end

    # Costruisce URL WhatsApp con messaggio precomposto
    def build_whatsapp_url
      phone = clean_phone(@company.phone)
      return "" if phone.blank?

      # Assicura prefisso internazionale italiano
      number = phone.delete("+")
      number = "39#{number}" unless number.start_with?("39")

      message = "Buongiorno! Ho visto il sito demo di #{@company.name} " \
                "e vorrei maggiori informazioni. Grazie!"
      "https://wa.me/#{number}?text=#{ERB::Util.url_encode(message)}"
    end

    # Rimuove caratteri non numerici eccetto il + iniziale
    def clean_phone(phone)
      return "" if phone.blank?

      phone.to_s.gsub(/[^\d+]/, "")
    end
  end
end
