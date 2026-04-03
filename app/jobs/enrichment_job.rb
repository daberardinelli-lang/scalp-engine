class EnrichmentJob < ApplicationJob
  queue_as :enrichment

  # Ritenta con backoff crescente — il browser headless può occasionalmente fallire
  retry_on Discovery::BrowserService::BrowserError, wait: :polynomially_longer, attempts: 3
  retry_on StandardError,                           wait: :polynomially_longer, attempts: 2
  discard_on ActiveJob::DeserializationError

  # Parametri:
  #   company_id:  Integer — ID della Company da arricchire (nil = batch tutte le discovered)
  #   enrich_mode: "full" (email + recensioni) | "email_only" (solo email, più veloce)
  def perform(company_id: nil, enrich_mode: "full")
    if company_id.present?
      enrich_single(company_id, enrich_mode)
    else
      enrich_batch(enrich_mode)
    end
  end

  private

  # ─── Singola company ───────────────────────────────────────────────────────

  def enrich_single(company_id, enrich_mode)
    company = Company.kept.find(company_id)

    unless company.status == "discovered"
      Rails.logger.info "[EnrichmentJob] Skip company_id=#{company_id}: status=#{company.status}"
      return
    end

    Rails.logger.info "[EnrichmentJob] Arricchimento company_id=#{company_id} mode=#{enrich_mode}"

    result = Discovery::EnrichmentService.call(company: company, enrich_mode: enrich_mode)

    log_result(result)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[EnrichmentJob] Company #{company_id} non trovata — discard"
  end

  # ─── Batch: tutte le discovered ───────────────────────────────────────────

  def enrich_batch(enrich_mode)
    companies = Company.kept
                       .where(status: "discovered")
                       .where(opted_out_at: nil)
                       .order(:created_at)

    Rails.logger.info "[EnrichmentJob] Batch: #{companies.count} aziende da arricchire (mode=#{enrich_mode})"

    companies.find_each do |company|
      EnrichmentJob.perform_later(company_id: company.id, enrich_mode: enrich_mode)
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
