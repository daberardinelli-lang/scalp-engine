# app/services/discovery/strategies/pagine_gialle_strategy.rb
#
# Cerca l'email di un'azienda su PagineGialle.it (no browser — solo HTTP + Nokogiri).
#
# Strategia (2 tentativi):
#   1. Ricerca cosa/dove: "{nome}/{città}" — formato strutturato PG, match migliore
#   2. Ricerca libera: "{nome} {città}" — fallback se la prima non trova
#   3. Verifica nome: il risultato deve corrispondere all'azienda cercata
#   4. Verifica indirizzo: se disponibile, confronta anche via/indirizzo
#   5. Estrae email dalla scheda dettaglio
#
# Restituisce: { email: "...", source: "paginegialle" } oppure nil

module Discovery
  module Strategies
    class PagineGialleStrategy
      BASE_URL    = "https://www.paginegialle.it"
      EMAIL_REGEX = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/

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
        # Tentativo 1: ricerca strutturata cosa/dove (più precisa)
        detail_url = search_cosa_dove
        # Tentativo 2: ricerca libera nome+città
        detail_url ||= search_libera

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

      # ─── Ricerca cosa/dove ─────────────────────────────────────────────────

      def search_cosa_dove
        return nil if @company.city.blank?

        cosa = CGI.escape(@company.name)
        dove = CGI.escape(@company.city)
        url = "#{BASE_URL}/ricerca/#{cosa}/#{dove}"

        find_matching_listing(url)
      end

      # ─── Ricerca libera ────────────────────────────────────────────────────

      def search_libera
        query = CGI.escape("#{@company.name} #{@company.city}")
        url = "#{BASE_URL}/ricerca/#{query}"

        find_matching_listing(url)
      end

      # ─── Trova il risultato corrispondente ─────────────────────────────────

      def find_matching_listing(search_url)
        html = fetch_html(search_url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)
        company_words = significant_words(@company.name)

        doc.css("div.search-itm").each do |itm|
          link = extract_detail_link(itm)
          next if link.nil?

          itm_name = itm.css("h2").text.to_s.strip.downcase
          itm_address = itm.css(".search-itm__adr, [class*='adr']").text.to_s.strip.downcase

          # Match per nome: score basato su quante parole significative corrispondono
          name_score = company_words.count { |w| itm_name.include?(w) }
          long_match = company_words.any? { |w| w.length >= 6 && itm_name.include?(w) }

          # Match per indirizzo: se abbiamo l'indirizzo, verifichiamo anche quello
          address_match = false
          if @company.address.present?
            addr_words = significant_words(@company.address)
            address_match = addr_words.any? { |w| w.length >= 4 && itm_address.include?(w) }
          end

          # Match per telefono nel testo del risultato
          phone_match = false
          if @company.phone.present?
            clean_phone = @company.phone.gsub(/\s+/, "").last(6)
            itm_text = itm.text.gsub(/\s+/, "")
            phone_match = clean_phone.length >= 6 && itm_text.include?(clean_phone)
          end

          # Accetta il risultato se:
          # - Telefono corrisponde (match più affidabile)
          # - Nome ha 2+ parole significative in comune
          # - Nome ha 1 parola lunga (>=6) + indirizzo corrisponde
          # - Nome ha 1 parola lunga (>=6) e poche parole significative totali
          accepted = phone_match ||
                     name_score >= 2 ||
                     (long_match && address_match) ||
                     (long_match && company_words.length <= 2)

          if accepted
            Rails.logger.debug "[PagineGialleStrategy] Match: '#{itm_name[0..50]}' " \
                               "(name_score=#{name_score} long=#{long_match} addr=#{address_match} phone=#{phone_match})"
            return link
          end
        end

        nil
      end

      def extract_detail_link(itm)
        link = itm.css("a[href]").find do |a|
          href = a["href"].to_s
          href.match?(%r{paginegialle\.it/[a-z]}) &&
            !href.include?("/ricerca/") &&
            !href.include?("/magazine") &&
            !href.include?("/categori")
        end
        return nil if link.nil?

        href = link["href"].to_s
        href.start_with?("http") ? href : "#{BASE_URL}#{href}"
      end

      # ─── Estrazione email ──────────────────────────────────────────────────

      def extract_email_from_page(url)
        html = fetch_html(url)
        return nil if html.nil?

        doc = Nokogiri::HTML(html)

        # 1. Cerca mailto: (salta quelli di condivisione con subject=)
        doc.css("a[href^='mailto:']").each do |mailto|
          href = mailto["href"].to_s
          next if href.include?("subject=")
          email = href.sub(/\Amailto:/i, "").split("?").first.strip
          return email if valid_email?(email)
        end

        # 2. Cerca email nel testo della pagina
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
          f.response :follow_redirects rescue nil
        end
      end

      # ─── Match nome ────────────────────────────────────────────────────────

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
        rieti terni perugia viterbo latina frosinone
        agriturismo locanda villa masseria cascina
      ].freeze

      def significant_words(name)
        name.to_s.downcase
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
