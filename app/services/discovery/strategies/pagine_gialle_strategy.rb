# app/services/discovery/strategies/pagine_gialle_strategy.rb
#
# Cerca l'email di un'azienda su PagineGialle.it (no browser — solo HTTP + Nokogiri).
# PagineGialle mostra spesso email nelle schede aziendali pubbliche.
#
# Strategia:
#   1. Cerca "{nome} {città}" su paginagialle.it
#   2. Apre la prima scheda corrispondente
#   3. Estrae email da link mailto: o pattern nel testo
#
# Restituisce: { email: "...", source: "paginegialle" } oppure nil

module Discovery
  module Strategies
    class PagineGialleStrategy
      BASE_URL    = "https://www.paginegialle.it"
      EMAIL_REGEX = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/

      # Domini email generici da escludere (appartengono a directory, non all'azienda)
      EXCLUDED_DOMAINS = %w[
        paginegialle.it pagineinterne.it paginebianche.it
        spaziofoto.it infobel.com google.com facebook.com
        example.com test.com
      ].freeze

      def self.call(company:, http_client: nil)
        new(company: company, http_client: http_client).call
      end

      def initialize(company:, http_client: nil)
        @company = company
        @client  = http_client || build_client
      end

      def call
        search_url  = build_search_url
        detail_url  = find_first_listing_url(search_url)
        return nil if detail_url.nil?

        email = extract_email_from_page(detail_url)
        return nil if email.nil?

        Rails.logger.info "[PagineGialleStrategy] Email trovata per #{@company.name}: #{email}"
        { "email" => email, "source" => "paginegialle" }
      rescue => e
        Rails.logger.warn "[PagineGialleStrategy] Errore per #{@company.name}: #{e.message}"
        nil
      end

      private

      # ─── Ricerca ───────────────────────────────────────────────────────────

      def build_search_url
        query = CGI.escape("#{@company.name} #{@company.city}")
        "#{BASE_URL}/ricerca/#{query}"
      end

      def find_first_listing_url(search_url)
        html = fetch_html(search_url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)

        # PagineGialle mostra i risultati in elementi con classe "listing-item"
        # Il link alla scheda è un <a> con href verso /pg/{slug}
        listing_link = doc.css("a.listing-item__name, a[href*='/pg/'], .listing h2 a, .title-company a")
                          .first

        return nil if listing_link.nil?

        href = listing_link["href"].to_s
        href.start_with?("http") ? href : "#{BASE_URL}#{href}"
      end

      # ─── Estrazione email ──────────────────────────────────────────────────

      def extract_email_from_page(url)
        html = fetch_html(url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)

        # 1. Cerca link mailto: (fonte più affidabile)
        mailto = doc.css("a[href^='mailto:']").first
        if mailto
          email = mailto["href"].sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # 2. Cerca pattern email nel testo visibile della pagina
        # Limitato ai tag rilevanti per evitare falsi positivi
        candidate_nodes = doc.css("p, span, div.contact, .email, [class*='email'], [class*='contact']")
        candidate_nodes.each do |node|
          match = node.text.scan(EMAIL_REGEX).first
          next if match.nil?
          return match if valid_email?(match)
        end

        nil
      end

      # ─── HTTP ─────────────────────────────────────────────────────────────

      def fetch_html(url)
        response = @client.get(url)
        response.status == 200 ? response.body : nil
      rescue Faraday::Error
        nil
      end

      def build_client
        Faraday.new do |f|
          f.headers["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                                    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
          f.headers["Accept-Language"] = "it-IT,it;q=0.9"
          f.options.timeout      = 15
          f.options.open_timeout = 8
          f.request :retry, max: 2, interval: 2.0,
                    exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
          f.response :follow_redirects rescue nil  # segui redirect (302)
        end
      end

      # ─── Validazione ──────────────────────────────────────────────────────

      def valid_email?(email)
        return false if email.blank?
        return false unless email.match?(EMAIL_REGEX)

        domain = email.split("@").last.to_s.downcase
        EXCLUDED_DOMAINS.none? { |excl| domain.end_with?(excl) }
      end
    end
  end
end
