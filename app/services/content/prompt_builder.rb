# app/services/content/prompt_builder.rb
#
# Costruisce il prompt utente da inviare a Claude API per la generazione
# dei contenuti della landing page demo.
#
# Il prompt include tutti i dati disponibili della Company:
#   - Nome, categoria, città
#   - Rating e numero di recensioni
#   - Testo delle migliori recensioni (fonte autentica per il copywriting)
#
# Uso:
#   Content::PromptBuilder.build(company: company)  # => String

module Content
  class PromptBuilder
    # Traduzione categoria → etichetta italiana leggibile
    CATEGORY_LABELS = {
      "restaurant"  => "Ristorante",
      "bar"         => "Bar / Caffetteria",
      "pizzeria"    => "Pizzeria",
      "plumber"     => "Idraulico",
      "electrician" => "Elettricista",
      "builder"     => "Impresa edile",
      "retail"      => "Negozio al dettaglio",
      "shop"        => "Negozio",
      "lawyer"      => "Studio legale",
      "accountant"  => "Studio commercialista",
      "notary"      => "Studio notarile",
      "other"       => "Attività commerciale"
    }.freeze

    def self.build(company:)
      new(company: company).build
    end

    def initialize(company:)
      @company = company
    end

    def build
      sections = []

      sections << "## Dati azienda"
      sections << "- Nome: #{@company.name}"
      sections << "- Categoria: #{category_label}"
      sections << "- Città: #{@company.city}" + (@company.province.present? ? " (#{@company.province})" : "")
      sections << "- Indirizzo: #{@company.address}" if @company.address.present?
      sections << "- Telefono: #{@company.phone}" if @company.phone.present?

      if @company.maps_rating.present?
        sections << "- Rating Google Maps: #{@company.maps_rating}/5 " \
                    "(#{@company.maps_reviews_count} recensioni)"
      end

      best = @company.best_reviews(limit: 3)
      if best.any?
        sections << ""
        sections << "## Recensioni reali dei clienti"
        sections << "(Usa queste testimonianze come ispirazione per il tono e i punti di forza)"
        best.each do |r|
          sections << "- \"#{r['text']}\" — #{r['author']} (#{r['rating']}/5)"
        end
      end

      sections << ""
      sections << "## Istruzione"
      sections << "Genera i contenuti per la landing page dimostrativa di questa " \
                  "#{category_label.downcase} italiana. " \
                  "Il tono deve essere professionale, caldo e in italiano. " \
                  "Usa i dati reali per rendere i contenuti specifici e credibili."

      sections.join("\n")
    end

    private

    def category_label
      CATEGORY_LABELS.fetch(@company.category, @company.category.humanize)
    end
  end
end
