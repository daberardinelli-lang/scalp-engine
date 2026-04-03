# app/services/discovery/strategies/google_search_strategy.rb
#
# Cerca l'email di un'azienda tramite DuckDuckGo Search.
# Strategia:
#   1. Cerca "Nome Azienda città email" su DuckDuckGo HTML
#   2. Estrae i primi 3 link dai risultati di ricerca
#   3. Visita ogni link e cerca email nella pagina (mailto: + regex)
#
# Restituisce: { email: "...", source: "web_search" } oppure nil

module Discovery
  module Strategies
    class GoogleSearchStrategy
      EMAIL_REGEX = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/

      EXCLUDED_EMAIL_DOMAINS = %w[
        google.com gmail.com facebook.com instagram.com twitter.com
        linkedin.com youtube.com wikipedia.org example.com test.com
        paginegialle.it paginebianche.it tripadvisor.it tripadvisor.com
        yelp.com booking.com thefork.it trustpilot.com
        duckduckgo.com yahoo.com bing.com microsoft.com
        w3.org schema.org wordpress.org jquery.com cloudflare.com sentry.io
      ].freeze

      # Domini da non visitare (social, directory — risultati non utili)
      SKIP_LINK_DOMAINS = %w[
        facebook.com instagram.com twitter.com linkedin.com youtube.com
        paginegialle.it paginebianche.it tripadvisor.it booking.com
        yelp.com thefork.it trustpilot.com wikipedia.org
      ].freeze

      MAX_LINKS = 3
      OPERATION_TIMEOUT = 15

      def self.call(company:, http_client: nil)
        new(company: company, http_client: http_client).call
      end

      def initialize(company:, http_client: nil)
        @company = company
        @client  = http_client || build_client
      end

      def call
        query = build_query
        Rails.logger.debug "[GoogleSearchStrategy] Query: #{query}"

        links = fetch_result_links(query)
        Rails.logger.debug "[GoogleSearchStrategy] Link trovati: #{links.size}"

        links.first(MAX_LINKS).each do |url|
          email = extract_email_from_page(url)
          if email
            Rails.logger.info "[GoogleSearchStrategy] Email trovata per #{@company.name}: #{email} (da #{url})"
            return { "email" => email, "source" => "web_search" }
          end
          sleep(1)
        end

        nil
      rescue => e
        Rails.logger.warn "[GoogleSearchStrategy] Errore per #{@company.name}: #{e.message}"
        nil
      end

      private

      def build_query
        name = @company.name.to_s.strip
        city = @company.city.to_s.strip
        "#{name} #{city} contatti email"
      end

      def fetch_result_links(query)
        encoded = CGI.escape(query)
        url = "https://html.duckduckgo.com/html/?q=#{encoded}"

        response = nil
        2.times do |attempt|
          response = @client.get(url)
          break if response.status == 200

          if response.status == 202 && attempt == 0
            sleep(5)
          else
            return []
          end
        end

        return [] unless response&.status == 200

        doc = Nokogiri::HTML(response.body)

        # DuckDuckGo HTML: i link dei risultati sono in a.result__a
        doc.css("a.result__a").filter_map do |a|
          href = a["href"].to_s
          # DuckDuckGo wrappa i link — estraiamo l'URL reale dal parametro uddg=
          if href.include?("uddg=")
            real_url = CGI.parse(URI.parse(href).query.to_s)["uddg"]&.first
            href = real_url if real_url.present?
          end

          next unless href.start_with?("http")
          next if SKIP_LINK_DOMAINS.any? { |d| href.include?(d) }

          href
        end.uniq
      rescue => e
        Rails.logger.debug "[GoogleSearchStrategy] Errore fetch links: #{e.message}"
        []
      end

      def extract_email_from_page(url)
        response = @client.get(url)
        return nil unless response.status == 200
        return nil unless response.headers["content-type"].to_s.include?("text/html")
        return nil if response.body.to_s.length > 500_000

        doc = Nokogiri::HTML(response.body)

        # 1. Cerca mailto:
        doc.css("a[href^='mailto:']").each do |mailto|
          href = mailto["href"].to_s
          next if href.include?("subject=") && !href.include?("@")
          email = href.sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # 2. Regex nel testo
        emails = doc.text.scan(EMAIL_REGEX).uniq
        emails.each { |e| return e if valid_email?(e) }

        nil
      rescue => e
        Rails.logger.debug "[GoogleSearchStrategy] Errore fetch page #{url}: #{e.class}"
        nil
      end

      def valid_email?(email)
        return false if email.blank?
        return false unless email.match?(EMAIL_REGEX)
        return false if email.length > 60

        domain = email.split("@").last.to_s.downcase
        EXCLUDED_EMAIL_DOMAINS.none? { |excl| domain.end_with?(excl) }
      end

      def build_client
        Faraday.new do |f|
          f.headers["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                                    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
          f.headers["Accept-Language"] = "it-IT,it;q=0.9"
          f.headers["Accept"] = "text/html,application/xhtml+xml"
          f.options.timeout      = OPERATION_TIMEOUT
          f.options.open_timeout = 8
          f.request :retry, max: 1, interval: 2.0,
                    exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        end
      end
    end
  end
end
