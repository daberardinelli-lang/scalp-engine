class DiscoveryJob < ApplicationJob
  queue_as :discovery

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Parametri:
  #   category: String   (es: "restaurant") — deve essere in Company::CATEGORIES
  #   location: String   (es: "Prato, Italia")
  #   radius:   Integer  (metri, default: 15_000 — usato come bias nella ricerca)
  def perform(category:, location:, radius: 15_000)
    raise ArgumentError, "Categoria non valida: #{category}" unless Company::CATEGORIES.include?(category)

    Rails.logger.info "[DiscoveryJob] START category=#{category} location=#{location} radius=#{radius}"

    result = Discovery::GooglePlacesService.call(
      category: category,
      location: location,
      radius:   radius
    )

    Rails.logger.info "[DiscoveryJob] DONE — " \
                      "trovate=#{result.total_found} " \
                      "salvate=#{result.companies.size} " \
                      "scartate_con_sito=#{result.skipped_count} " \
                      "errori=#{result.errors.size}"

    result.errors.each do |err|
      Rails.logger.warn "[DiscoveryJob] ERROR: #{err}"
    end

    result
  end
end
