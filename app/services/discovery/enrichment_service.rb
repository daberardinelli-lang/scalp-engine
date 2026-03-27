# app/services/discovery/enrichment_service.rb
#
# Orchestratore principale della Fase 2 — Enrichment.
# Riceve una Company in stato "discovered" e la porta a "enriched" raccogliendo:
#   - Recensioni Google Maps (via Places API)
#   - Email di contatto (via PagineGialle → Facebook)
#
# Uso:
#   result = Discovery::EnrichmentService.call(company: company)
#   result.success?       # => true / false
#   result.email_found?   # => true se email trovata
#   result.reviews_count  # => numero recensioni salvate
#   result.errors         # => Array<String>

module Discovery
  class EnrichmentService
    Result = Struct.new(:company, :email_found, :reviews_count, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end

      def email_found?
        email_found
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(company:,
                   review_fetcher:  Discovery::ReviewFetcherService,
                   email_extractor: Discovery::EmailExtractorService)
      @company         = company
      @review_fetcher  = review_fetcher
      @email_extractor = email_extractor
      @errors          = []
    end

    def call
      validate_company!

      Rails.logger.info "[EnrichmentService] START company_id=#{@company.id} name=#{@company.name}"

      reviews_count = fetch_reviews
      email_found   = extract_email

      finalize_enrichment

      Rails.logger.info "[EnrichmentService] DONE company_id=#{@company.id} " \
                        "email_found=#{email_found} reviews=#{reviews_count} errors=#{@errors.size}"

      Result.new(
        company:       @company,
        email_found:   email_found,
        reviews_count: reviews_count,
        errors:        @errors
      )
    rescue ArgumentError => e
      Rails.logger.warn "[EnrichmentService] SKIP company_id=#{@company.id}: #{e.message}"
      Result.new(company: @company, email_found: false, reviews_count: 0, errors: [e.message])
    end

    private

    # ─── Validazione ──────────────────────────────────────────────────────────

    def validate_company!
      unless @company.google_place_id.present?
        raise ArgumentError, "Company senza google_place_id — impossibile arricchire"
      end

      if @company.opted_out?
        raise ArgumentError, "Company ha fatto opt-out — skip arricchimento"
      end

      if @company.discarded?
        raise ArgumentError, "Company eliminata — skip arricchimento"
      end
    end

    # ─── Step 1: Recensioni ───────────────────────────────────────────────────

    def fetch_reviews
      result = @review_fetcher.call(
        google_place_id: @company.google_place_id
      )

      if result.error
        @errors << "ReviewFetcher: #{result.error}"
        return 0
      end

      if result.reviews.any?
        @company.reviews_data = result.reviews
        Rails.logger.debug "[EnrichmentService] #{result.reviews.size} recensioni trovate"
      end

      result.reviews.size
    rescue => e
      @errors << "ReviewFetcher eccezione: #{e.message}"
      0
    end

    # ─── Step 2: Email ────────────────────────────────────────────────────────

    def extract_email
      result = @email_extractor.call(company: @company)

      if result.status == "found"
        @company.email        = result.email
        @company.email_source = result.source
        @company.email_status = "found"
        return true
      else
        @company.email_status = "unknown" if @company.email_status == "unknown"
        return false
      end
    rescue => e
      @errors << "EmailExtractor eccezione: #{e.message}"
      false
    end

    # ─── Step 3: Persistenza e avanzamento status ─────────────────────────────

    def finalize_enrichment
      @company.status      = "enriched"
      @company.enriched_at = Time.current

      unless @company.save
        err = "Save fallito: #{@company.errors.full_messages.join(', ')}"
        @errors << err
        Rails.logger.error "[EnrichmentService] #{err}"
      end
    end
  end
end
