# app/services/discovery/strategies/website_strategy.rb
#
# Cerca l'email di un'azienda direttamente sul suo sito web.
# Usa il campo company.website (salvato da Places API).
#
# Strategia:
#   1. Visita la homepage del sito
#   2. Cerca email nella pagina (mailto: + regex)
#   3. Se non trovata, prova la pagina /contatti o /contattaci o /contact
#   4. Estrae email dal DOM
#
# Restituisce: { email: "...", source: "website" } oppure nil

module Discovery
  module Strategies
    class WebsiteStrategy
      EMAIL_REGEX = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/

      EXCLUDED_DOMAINS = %w[
        google.com facebook.com instagram.com twitter.com
        example.com test.com sentry.io w3.org schema.org
        wordpress.org jquery.com cloudflare.com
      ].freeze

      # Pagine di contatto comuni per siti italiani
      CONTACT_PATHS = %w[
        /contatti /contattaci /contact /contacts /chi-siamo
        /about /info /dove-siamo /contact-us
      ].freeze

      OPERATION_TIMEOUT = 20

      def self.call(company:, http_client: nil)
        new(company: company, http_client: http_client).call
      end

      def initialize(company:, http_client: nil)
        @company = company
        @client  = http_client || build_client
      end

      def call
        website = @company.website.to_s.strip
        return nil if website.blank?

        # Normalizza URL
        website = "https://#{website}" unless website.start_with?("http")
        base_url = website.chomp("/")

        Rails.logger.debug "[WebsiteStrategy] Scansione #{base_url}"

        # Step 1: homepage
        email = extract_email_from_url(base_url)
        if email
          Rails.logger.info "[WebsiteStrategy] Email trovata in homepage per #{@company.name}: #{email}"
          return { "email" => email, "source" => "website" }
        end

        # Step 2: pagine di contatto
        CONTACT_PATHS.each do |path|
          email = extract_email_from_url("#{base_url}#{path}")
          if email
            Rails.logger.info "[WebsiteStrategy] Email trovata in #{path} per #{@company.name}: #{email}"
            return { "email" => email, "source" => "website" }
          end
        end

        nil
      rescue => e
        Rails.logger.warn "[WebsiteStrategy] Errore per #{@company.name}: #{e.message}"
        nil
      end

      private

      def extract_email_from_url(url)
        html = fetch_html(url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)

        # 1. Cerca mailto: (fonte più affidabile)
        doc.css("a[href^='mailto:']").each do |mailto|
          href = mailto["href"].to_s
          next if href.include?("subject=") && !href.include?("@")
          email = href.sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # 2. Cerca pattern email nel testo visibile
        # Limitato a sezioni rilevanti per evitare email di framework/plugin
        relevant_sections = doc.css(
          "main, #content, .content, .contact, .contatti, footer, " \
          "[class*='contact'], [class*='contatt'], [id*='contact'], [id*='contatt'], " \
          "p, address, .footer, #footer"
        )

        if relevant_sections.any?
          emails = relevant_sections.text.scan(EMAIL_REGEX).uniq
        else
          # Fallback: intero body
          emails = doc.text.scan(EMAIL_REGEX).uniq
        end

        emails.each do |email|
          return email if valid_email?(email)
        end

        nil
      rescue => e
        Rails.logger.debug "[WebsiteStrategy] Errore fetch #{url}: #{e.message}"
        nil
      end

      def fetch_html(url)
        response = @client.get(url)
        return nil unless response.status == 200
        return nil unless response.headers["content-type"].to_s.include?("text/html")

        body = response.body.to_s
        # Salta pagine troppo grandi (probabilmente non HTML utile)
        return nil if body.length > 500_000

        body
      rescue Faraday::Error
        nil
      end

      def valid_email?(email)
        return false if email.blank?
        return false unless email.match?(EMAIL_REGEX)
        return false if email.length > 60

        domain = email.split("@").last.to_s.downcase
        EXCLUDED_DOMAINS.none? { |excl| domain.end_with?(excl) }
      end

      def build_client
        Faraday.new do |f|
          f.headers["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                                    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
          f.headers["Accept-Language"] = "it-IT,it;q=0.9"
          f.headers["Accept"] = "text/html,application/xhtml+xml"
          f.options.timeout      = 10
          f.options.open_timeout = 5
          f.request :retry, max: 1, interval: 1.0,
                    exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
          f.response :follow_redirects rescue nil
        end
      end
    end
  end
end
