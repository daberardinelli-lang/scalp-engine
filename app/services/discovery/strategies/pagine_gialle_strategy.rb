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

        # PagineGialle struttura 2024+: div.search-itm contiene le schede aziendali
        # Il link alla scheda è un <a> con href verso paginegialle.it/{slug}
        #
        # IMPORTANTE: prendiamo SOLO risultati il cui nome corrisponde all'azienda cercata.
        # Nessun fallback al primo risultato — meglio nessuna email che un'email sbagliata.
        company_words = significant_words(@company.name)

        doc.css("div.search-itm").each do |itm|
          link = itm.css("a[href]").find do |a|
            href = a["href"].to_s
            href.match?(%r{paginegialle\.it/[a-z]}) &&
              !href.include?("/ricerca/") &&
              !href.include?("/magazine") &&
              !href.include?("/categori")
          end
          next if link.nil?

          # Verifica match nome: almeno 2 parole significative in comune,
          # oppure 1 parola se è lunga (>=6 chars, probabilmente un cognome/nome unico)
          itm_name = itm.css("h2").text.to_s.strip.downcase
          matching_words = company_words.count { |w| itm_name.include?(w) }
          long_match = company_words.any? { |w| w.length >= 6 && itm_name.include?(w) }
          next unless matching_words >= 2 || long_match

          href = link["href"].to_s
          return href.start_with?("http") ? href : "#{BASE_URL}#{href}"
        end

        nil
      end

      # ─── Estrazione email ──────────────────────────────────────────────────

      def extract_email_from_page(url)
        html = fetch_html(url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)

        # 1. Cerca link mailto: che contengano email dell'azienda (non "segnala ad amico")
        doc.css("a[href^='mailto:']").each do |mailto|
          href = mailto["href"].to_s
          # Salta i mailto di condivisione PagineGialle (contengono subject= nel link)
          next if href.include?("subject=")
          email = href.sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # 2. Cerca pattern email nel testo visibile dell'intera pagina
        # PagineGialle mostra l'email in vari contenitori non predicibili
        all_emails = doc.text.scan(EMAIL_REGEX).uniq
        all_emails.each do |email|
          return email if valid_email?(email)
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

      # ─── Match nome ────────────────────────────────────────────────────────

      # Stop-words italiane comuni nei nomi aziendali — non significative per il match
      STOP_WORDS = %w[
        del della delle dei degli di da in con per tra fra alla alle
        studio studi associato associati dott dottssa dottore dottoressa prof
        srl sas snc spa srls consulenza consulente consulenti lavoro
        societa azienda impresa centro gruppo servizi servizio
        ristorante trattoria osteria pizzeria taverna albergo hotel
        negozio bottega laboratorio officina farmacia bar caffe
        pesce carne pizza pasta gelato forno panificio pasticceria
        medico medici dentista avvocato notaio commercialista
        roma milano napoli torino firenze bologna palermo genova
      ].freeze

      def significant_words(name)
        name.downcase
            .gsub(/[^a-zàèéìòù\s]/, " ")
            .split(/\s+/)
            .select { |w| w.length > 3 }
            .reject { |w| STOP_WORDS.include?(w) }
            .uniq
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
