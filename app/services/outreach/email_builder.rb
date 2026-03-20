# app/services/outreach/email_builder.rb
#
# Costruisce l'oggetto e il corpo HTML dell'email di outreach usando
# un template Liquid. Include pixel di tracking, link tracciati e opt-out.
#
# Uso:
#   result = Outreach::EmailBuilder.build(company:, demo:, lead:)
#   result.subject  # => "Ristorante Bella Italia — abbiamo una sorpresa per voi 🎁"
#   result.html     # => "<html>...</html>"
#
module Outreach
  class EmailBuilder
    TEMPLATE_PATH = Rails.root.join("app", "views", "outreach", "email.html.liquid").freeze

    Result = Struct.new(:subject, :html, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    def self.build(company:, demo:, lead:)
      new(company: company, demo: demo, lead: lead).build
    end

    def initialize(company:, demo:, lead:)
      @company = company
      @demo    = demo
      @lead    = lead
    end

    def build
      template_source = File.read(TEMPLATE_PATH)
      liquid           = Liquid::Template.parse(template_source, error_mode: :warn)
      html             = liquid.render(build_assigns, strict_variables: false)

      Result.new(subject: build_subject, html: html, errors: [])
    rescue Liquid::Error => e
      Result.new(subject: nil, html: nil, errors: ["Liquid error: #{e.message}"])
    rescue Errno::ENOENT => e
      Result.new(subject: nil, html: nil, errors: ["Template non trovato: #{e.message}"])
    rescue => e
      Result.new(subject: nil, html: nil, errors: ["EmailBuilder error: #{e.message}"])
    end

    private

    def build_subject
      "#{@company.name} — abbiamo creato un sito demo per voi 🌐"
    end

    def build_assigns
      {
        # Azienda
        "company_name"        => @company.name.to_s,
        "city"                => @company.city.to_s,
        "maps_rating"         => @company.maps_rating.to_s,
        "maps_reviews_count"  => @company.maps_reviews_count.to_s,

        # Demo
        "headline"            => @demo.generated_headline.to_s,
        "about_excerpt"       => @demo.generated_about.to_s.truncate(160, omission: ""),
        "cta_text"            => @demo.generated_cta.to_s,

        # URL tracciati
        "demo_link_url"       => tracking_url("click"),
        "open_pixel_url"      => tracking_url("open"),
        "optout_url"          => tracking_url("optout"),

        # Brand
        "brand_name"          => ENV.fetch("BRAND_NAME", "WebRadar"),
        "brand_email"         => ENV.fetch("BRAND_EMAIL", "info@webradar.it")
      }
    end

    def tracking_url(action)
      base = ENV.fetch("APP_BASE_URL", "http://localhost:3000")
      "#{base}/t/#{@lead.tracking_token}/#{action}"
    end
  end
end
