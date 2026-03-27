# app/services/discovery/strategies/facebook_strategy.rb
#
# Cerca l'email di un'azienda sulla sua pagina Facebook (sezione "Informazioni").
# Usa Ferrum (Chrome headless) perché Facebook richiede JavaScript.
#
# Strategia:
#   1. Cerca "{nome} {città}" su Facebook Pages Search
#   2. Apre la prima pagina pertinente
#   3. Naviga alla sezione "Informazioni" / "About"
#   4. Estrae email dal DOM
#
# Restituisce: { email: "...", source: "facebook" } oppure nil

module Discovery
  module Strategies
    class FacebookStrategy
      EMAIL_REGEX = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/

      EXCLUDED_DOMAINS = %w[
        facebook.com fb.com sentry.io example.com
        google.com instagram.com
      ].freeze

      # Timeout massimo per tutta l'operazione Facebook (in secondi)
      OPERATION_TIMEOUT = 45

      def self.call(company:)
        new(company: company).call
      end

      def initialize(company:)
        @company = company
      end

      def call
        Timeout.timeout(OPERATION_TIMEOUT) do
          Discovery::BrowserService.with_browser do |browser|
            search_and_extract(browser)
          end
        end
      rescue Timeout::Error
        Rails.logger.warn "[FacebookStrategy] Timeout per #{@company.name}"
        nil
      rescue Discovery::BrowserService::BrowserError => e
        Rails.logger.warn "[FacebookStrategy] Browser error per #{@company.name}: #{e.message}"
        nil
      rescue => e
        Rails.logger.warn "[FacebookStrategy] Errore per #{@company.name}: #{e.message}"
        nil
      end

      private

      def search_and_extract(browser)
        page_url = find_facebook_page(browser)
        return nil if page_url.nil?

        email = extract_email_from_about(browser, page_url)
        return nil if email.nil?

        Rails.logger.info "[FacebookStrategy] Email trovata per #{@company.name}: #{email}"
        { "email" => email, "source" => "facebook" }
      end

      # ─── Step 1: trova la pagina Facebook ─────────────────────────────────

      def find_facebook_page(browser)
        query       = CGI.escape("#{@company.name} #{@company.city}")
        search_url  = "https://www.facebook.com/search/pages/?q=#{query}"

        browser.go_to(search_url)
        browser.network.wait_for_idle(duration: 2)

        # Prendi il primo risultato di ricerca — link a una pagina /pages/ o /@slug
        page_link = browser.css("a[href*='/pages/'], a[href*='facebook.com/']").find do |el|
          href = el.attribute("href").to_s
          href.match?(%r{facebook\.com/(?:pages/|@)?[a-z0-9.\-]+}i) &&
            !href.include?("search") &&
            !href.include?("login")
        end

        return nil if page_link.nil?

        href = page_link.attribute("href").to_s
        # Normalizza URL
        href.split("?").first
      rescue => e
        Rails.logger.debug "[FacebookStrategy] find_facebook_page error: #{e.message}"
        nil
      end

      # ─── Step 2: apri la pagina → sezione About → estrai email ───────────

      def extract_email_from_about(browser, page_url)
        about_url = page_url.chomp("/") + "/about"
        browser.go_to(about_url)
        browser.network.wait_for_idle(duration: 2)

        # Cerca mailto: nel DOM
        mailto_links = browser.css("a[href^='mailto:']")
        mailto_links.each do |el|
          href  = el.attribute("href").to_s
          email = href.sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # Fallback: cerca pattern email nel testo della pagina
        body_text = browser.body
        candidates = body_text.scan(EMAIL_REGEX)
        candidates.each do |email|
          return email if valid_email?(email)
        end

        nil
      rescue => e
        Rails.logger.debug "[FacebookStrategy] extract_email_from_about error: #{e.message}"
        nil
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
