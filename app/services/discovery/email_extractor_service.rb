# app/services/discovery/email_extractor_service.rb
#
# Orchestratore per la ricerca dell'email di un'azienda.
# Prova le strategie in sequenza, si ferma alla prima che trova qualcosa.
#
# Pipeline:
#   1. PagineGialleStrategy — veloce, no browser, buona copertura PMI italiane
#   2. FacebookStrategy     — browser headless Ferrum, fallback robusto
#
# Uso:
#   result = Discovery::EmailExtractorService.call(company: company)
#   result.email    # => "info@esempio.it" | nil
#   result.source   # => "paginegialle" | "facebook" | nil
#   result.status   # => "found" | "unknown"

module Discovery
  class EmailExtractorService
    # Pipeline di strategie in ordine di affidabilità/velocità:
    #   1. Website      — sito ufficiale dell'azienda (più affidabile)
    #   2. PagineGialle — directory business italiana (buona copertura PMI)
    #   3. GoogleSearch  — cerca email nei risultati Google (ampia copertura)
    STRATEGIES = [
      Strategies::WebsiteStrategy,
      Strategies::PagineGialleStrategy,
      Strategies::GoogleSearchStrategy
    ].freeze

    # Delay tra una strategia e l'altra (cortesia verso i server)
    INTER_STRATEGY_DELAY = 2

    Result = Struct.new(:email, :source, :status, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      # Skip se l'email è già nota
      if @company.email_status == "found" && @company.email.present?
        Rails.logger.info "[EmailExtractorService] #{@company.name}: email già presente, skip"
        return Result.new(email: @company.email, source: @company.email_source, status: "found")
      end

      # Skip se esplicitamente marcata da saltare
      if @company.email_status == "skip"
        Rails.logger.info "[EmailExtractorService] #{@company.name}: status=skip, skip"
        return Result.new(email: nil, source: nil, status: "skip")
      end

      Rails.logger.info "[EmailExtractorService] Ricerca email per: #{@company.name} (#{@company.city})"

      STRATEGIES.each_with_index do |strategy_class, idx|
        sleep(INTER_STRATEGY_DELAY) if idx > 0

        strategy_name = strategy_class.name.demodulize
        Rails.logger.debug "[EmailExtractorService] Provo #{strategy_name}..."

        found = run_strategy(strategy_class)
        next if found.nil?

        Rails.logger.info "[EmailExtractorService] Trovata via #{found['source']}: #{found['email']}"
        return Result.new(email: found["email"], source: found["source"], status: "found")
      end

      Rails.logger.info "[EmailExtractorService] #{@company.name}: email non trovata"
      Result.new(email: nil, source: nil, status: "unknown")
    end

    private

    def run_strategy(strategy_class)
      strategy_class.call(company: @company)
    rescue => e
      Rails.logger.warn "[EmailExtractorService] #{strategy_class.name} fallita: #{e.message}"
      nil
    end
  end
end
