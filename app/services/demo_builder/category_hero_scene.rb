# app/services/demo_builder/category_hero_scene.rb
#
# Sceglie la clip video "hero" per una Company in base a nome+categoria.
# Le clip vivono in DEMO_STORAGE_PATH/_assets/video/<folder>/hero.mp4 e in
# produzione sono servite da nginx come /_assets/video/<folder>/hero.mp4.
#
# Stesso pattern di DemoBuilder::ServiceIcons.
#
# Uso:
#   folder = DemoBuilder::CategoryHeroScene.folder_for(company)  # => "enoteca" | "default" | nil
#   DemoBuilder::CategoryHeroScene.video_url(folder)             # => "/_assets/video/enoteca/hero.mp4"
#
module DemoBuilder
  module CategoryHeroScene
    # Regole keyword → folder (su "nome categoria" in minuscolo, prima che matcha vince).
    KEYWORD_RULES = [
      [ "enoteca",     [ "vini", "vino", "cantina", "enotec", "wine bar" ] ],
      [ "pizzeria",    [ "pizz" ] ],
      [ "bar",         [ "bar", "caff", "caffetteria" ] ],
      [ "pasticceria", [ "pasticc", "dolc", "gelat" ] ],
      [ "macelleria",  [ "macell", "brace", "grigl" ] ],
      [ "ristorante",  [ "ristorant", "trattoria", "osteria", "hostaria" ] ],
      [ "barbiere",    [ "barbier", "parrucch", "hair" ] ],
      [ "estetica",    [ "estetic", "beauty", "spa", "benesser" ] ],
      [ "artigiano",   [ "artigian", "falegnam" ] ],
      [ "negozio",     [ "negozio", "boutique" ] ],
      [ "studio",      [ "studio", "consulenz", "avvocat", "commercialist" ] ],
      [ "struttura",   [ "b&b", "hotel", "agriturismo", "affittacamere" ] ]
    ].freeze

    # Fallback sulla categoria larga di Company.
    CATEGORY_FALLBACK = {
      "restaurant"    => "ristorante",
      "artisan"       => "artigiano",
      "shop"          => "negozio",
      "professional"  => "studio",
      "beauty"        => "estetica",
      "accommodation" => "struttura"
    }.freeze

    module_function

    # Folder della clip da usare, o nil se non c'è alcun video utilizzabile.
    def folder_for(company)
      candidate = match_keyword(company) || CATEGORY_FALLBACK[company.category.to_s]

      return candidate if candidate.present? && video_exists?(candidate)
      return "default" if video_exists?("default")

      nil
    end

    def video_url(folder)
      "/_assets/video/#{folder}/hero.mp4"
    end

    # Folder dal match fine per keyword (ignora l'esistenza del file). Utile nei test.
    def match_keyword(company)
      text = "#{company.name} #{company.category}".downcase
      rule = KEYWORD_RULES.find { |_folder, kws| kws.any? { |kw| text.include?(kw) } }
      rule&.first
    end

    def video_exists?(folder)
      return false if folder.blank?

      File.exist?(video_path(folder))
    end

    def video_path(folder)
      File.join(storage_base, "_assets", "video", folder, "hero.mp4")
    end

    # Base UNICA per File.exist? e per la mappatura nginx /_assets → DEMO_STORAGE_PATH/_assets.
    # In Docker è il named volume demos_storage (NON storage/demos del repo).
    def storage_base
      ENV["DEMO_STORAGE_PATH"].presence || Rails.root.join("storage", "demos").to_s
    end
  end
end
