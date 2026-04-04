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

    def self.render(demo:)
      new(demo: demo).render
    end

    def initialize(demo:)
      @demo    = demo
      @company = demo.company
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
        "services"           => @demo.services_list,
        "cta_text"           => @demo.generated_cta.to_s,

        # Foto: prima foto separata per hero about, resto per gallery
        "first_photo"        => (@company.maps_photo_urls.first || "").to_s,
        "photos"             => (@company.maps_photo_urls[1..] || []),

        # Recensioni: solo quelle con testo e rating ≥ 4
        "reviews"            => best_reviews,

        # WhatsApp: link diretto con messaggio precomposto
        "whatsapp_url"       => build_whatsapp_url,

        # Google Maps Embed (per iframe nella sezione contatti)
        "google_maps_embed_key" => ENV.fetch("GOOGLE_PLACES_API_KEY", ""),

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
