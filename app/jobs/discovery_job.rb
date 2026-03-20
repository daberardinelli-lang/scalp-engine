class DiscoveryJob < ApplicationJob
  queue_as :discovery

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Parametri (modalità classica — category fissa):
  #   category:    String   (es: "restaurant") — deve essere in Company::CATEGORIES
  #   location:    String   (es: "Prato, Italia")
  #   radius:      Integer  (metri, default: 15_000)
  #
  # Parametri (modalità Campaign — query libera):
  #   campaign_id: Integer  — ID della Campaign
  #   location:    String
  #   radius:      Integer  (default: 15_000)
  def perform(location:, radius: 15_000, category: nil, campaign_id: nil)
    if campaign_id.present?
      perform_campaign_discovery(campaign_id: campaign_id, location: location, radius: radius)
    else
      perform_category_discovery(category: category, location: location, radius: radius)
    end
  end

  private

  def perform_category_discovery(category:, location:, radius:)
    raise ArgumentError, "Categoria non valida: #{category}" unless Company::CATEGORIES.include?(category)

    Rails.logger.info "[DiscoveryJob] START category=#{category} location=#{location} radius=#{radius}"

    result = Discovery::GooglePlacesService.call(
      category: category,
      location: location,
      radius:   radius
    )

    log_result(result)
    result
  end

  def perform_campaign_discovery(campaign_id:, location:, radius:)
    campaign = Campaign.find(campaign_id)
    query    = campaign.discovery_query.presence || campaign.target_profile

    raise ArgumentError, "Campagna #{campaign_id} senza query di ricerca definita." if query.blank?

    # Outreach mode: include anche prospect con sito web (medici, tabaccai, etc.)
    # Web Agency mode: salta chi ha già un sito
    skip_websites = campaign.skip_websites?

    Rails.logger.info "[DiscoveryJob] CAMPAIGN START campaign=#{campaign.name} query=#{query} " \
                      "location=#{location} radius=#{radius} skip_websites=#{skip_websites}"

    result = Discovery::GooglePlacesService.call(
      query:         query,
      location:      location,
      radius:        radius,
      campaign_id:   campaign_id,
      skip_websites: skip_websites
    )

    log_result(result)
    result
  end

  def log_result(result)
    Rails.logger.info "[DiscoveryJob] DONE — " \
                      "trovate=#{result.total_found} " \
                      "salvate=#{result.companies.size} " \
                      "scartate_con_sito=#{result.skipped_count} " \
                      "errori=#{result.errors.size}"

    result.errors.each do |err|
      Rails.logger.warn "[DiscoveryJob] ERROR: #{err}"
    end
  end
end
