class ContentGenerationJob < ApplicationJob
  queue_as :demo

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Parametri:
  #   company_id: Integer — ID della Company da processare
  #               oppure nil per batch su tutte le "enriched"
  def perform(company_id: nil)
    if company_id.present?
      generate_for_single(company_id)
    else
      generate_batch
    end
  end

  private

  # ─── Singola company ──────────────────────────────────────────────────────

  def generate_for_single(company_id)
    company = Company.kept.find(company_id)

    unless %w[enriched demo_built].include?(company.status)
      Rails.logger.info "[ContentGenerationJob] Skip company_id=#{company_id}: status=#{company.status}"
      return
    end

    Rails.logger.info "[ContentGenerationJob] Generazione contenuti company_id=#{company_id}"

    result = Content::GeneratorService.call(company: company)

    if result.success?
      Rails.logger.info "[ContentGenerationJob] OK company_id=#{company_id} " \
                        "demo_id=#{result.demo.id} subdomain=#{result.demo.subdomain}"
    else
      Rails.logger.warn "[ContentGenerationJob] WARN company_id=#{company_id}: " \
                        "#{result.errors.join(' | ')}"
      # Ritenta solo se ci sono errori di API (non di validazione)
      raise result.errors.first if result.errors.any? { |e| e.include?("HTTP error") || e.include?("Claude API error") }
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ContentGenerationJob] Company #{company_id} non trovata — discard"
  end

  # ─── Batch: tutte le enriched ─────────────────────────────────────────────

  def generate_batch
    companies = Company.kept
                       .where(status: "enriched")
                       .where(opted_out_at: nil)
                       .order(:created_at)

    Rails.logger.info "[ContentGenerationJob] Batch: #{companies.count} aziende da processare"

    companies.find_each do |company|
      ContentGenerationJob.perform_later(company_id: company.id)
      sleep(0.5)  # piccolo delay tra gli enqueue per rispettare rate limit Claude API
    end
  end
end
