class EnrichmentJob < ApplicationJob
  queue_as :enrichment

  # Ritenta con backoff crescente — il browser headless può occasionalmente fallire
  retry_on Discovery::BrowserService::BrowserError, wait: :polynomially_longer, attempts: 3
  retry_on StandardError,                           wait: :polynomially_longer, attempts: 2
  discard_on ActiveJob::DeserializationError

  # Parametri:
  #   company_id: Integer — ID della Company da arricchire
  #               oppure nil per processare tutte le "discovered" (batch)
  def perform(company_id: nil)
    if company_id.present?
      enrich_single(company_id)
    else
      enrich_batch
    end
  end

  private

  # ─── Singola company ───────────────────────────────────────────────────────

  def enrich_single(company_id)
    company = Company.kept.find(company_id)

    unless company.status == "discovered"
      Rails.logger.info "[EnrichmentJob] Skip company_id=#{company_id}: status=#{company.status}"
      return
    end

    Rails.logger.info "[EnrichmentJob] Arricchimento company_id=#{company_id}"

    result = Discovery::EnrichmentService.call(company: company)

    log_result(result)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[EnrichmentJob] Company #{company_id} non trovata — discard"
    # Non ritenta: la company non esiste
  end

  # ─── Batch: tutte le discovered ───────────────────────────────────────────

  def enrich_batch
    companies = Company.kept
                       .where(status: "discovered")
                       .where(opted_out_at: nil)
                       .order(:created_at)

    Rails.logger.info "[EnrichmentJob] Batch: #{companies.count} aziende da arricchire"

    companies.find_each do |company|
      # Enqueue job individuale invece di processare inline —
      # evita timeout del job e permette retry granulare
      EnrichmentJob.perform_later(company_id: company.id)

      # Piccolo delay tra gli enqueue per non saturare la coda
      sleep(0.1)
    end
  end

  def log_result(result)
    if result.success?
      Rails.logger.info "[EnrichmentJob] OK company_id=#{result.company.id} " \
                        "email_found=#{result.email_found?} reviews=#{result.reviews_count}"
    else
      Rails.logger.warn "[EnrichmentJob] WARN company_id=#{result.company.id} " \
                        "errors=#{result.errors.join(' | ')}"
    end
  end
end
