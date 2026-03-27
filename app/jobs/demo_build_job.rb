# app/jobs/demo_build_job.rb
#
# Costruisce il file HTML della demo per una singola azienda o in batch.
#
# Uso:
#   DemoBuildJob.perform_later(company_id: 42)   # singola
#   DemoBuildJob.perform_later                    # batch (tutte le demo_built)
#
class DemoBuildJob < ApplicationJob
  queue_as :demo

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  BATCH_ENQUEUE_DELAY = 0.1 # secondi tra un enqueue e l'altro

  def perform(company_id: nil)
    if company_id
      build_single(Company.kept.find(company_id))
    else
      run_batch
    end
  end

  private

  def build_single(company)
    demo = company.demo

    unless demo&.content_generated?
      Rails.logger.warn "[DemoBuildJob] Skip #{company.name}: contenuti AI non generati"
      return
    end

    result = DemoBuilder::TemplateRenderer.render(demo: demo)
    unless result.success?
      raise "TemplateRenderer failed for #{company.name}: #{result.errors.join(', ')}"
    end

    deploy_result = DemoBuilder::DeployService.call(demo: demo, html: result.html)
    unless deploy_result.success?
      raise "DeployService failed for #{company.name}: #{deploy_result.errors.join(', ')}"
    end

    Rails.logger.info "[DemoBuildJob] ✓ #{company.name} → #{deploy_result.html_path}"
  end

  def run_batch
    scope = Company.kept
                   .where(status: "demo_built")
                   .where(opted_out_at: nil)
                   .joins(:demo)
                   .merge(Demo.where.not(generated_headline: [nil, ""]))

    count = scope.count
    Rails.logger.info "[DemoBuildJob] Batch avviato: #{count} aziende"

    scope.find_each do |company|
      self.class.perform_later(company_id: company.id)
      sleep BATCH_ENQUEUE_DELAY
    end
  end
end
