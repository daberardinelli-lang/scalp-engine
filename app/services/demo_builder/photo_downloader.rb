# app/services/demo_builder/photo_downloader.rb
#
# Scarica le foto Google Maps di una Company e le salva come file statici
# nella cartella della demo: {DEMO_STORAGE_PATH}/{subdomain}/img/photo_N.jpg
#
# Motivo: gli URL del media endpoint di Google Places (New) scadono nel tempo
# (il photo resource name diventa invalido → 404) ed espongono la API key in
# chiaro nell'HTML pubblico. Scaricando le foto al momento del build:
#   - le immagini non scadono più (sono copie locali servite da nginx);
#   - la API key non finisce nell'HTML della demo;
#   - nessuna chiamata API a ogni visualizzazione.
#
# Restituisce i path relativi (es. "img/photo_1.jpg") da passare al renderer.
# Il download è best-effort: le foto fallite vengono saltate, non bloccano il build.
#
# Uso:
#   result = DemoBuilder::PhotoDownloader.call(demo: demo)
#   result.paths  # => ["img/photo_1.jpg", "img/photo_2.jpg"]
#
require "open-uri"

module DemoBuilder
  class PhotoDownloader
    MAX_PHOTOS   = 5
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    Result = Struct.new(:paths, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    # fetcher: callable iniettabile (url -> binary String) per testabilità.
    def self.call(demo:, fetcher: nil)
      new(demo: demo, fetcher: fetcher).call
    end

    def initialize(demo:, fetcher: nil)
      @demo    = demo
      @company = demo.company
      @fetcher = fetcher || method(:default_fetch)
      @errors  = []
    end

    def call
      urls = Array(@company.maps_photo_urls).first(MAX_PHOTOS)
      return Result.new(paths: [], errors: []) if urls.empty?

      img_dir = File.join(demo_directory, "img")
      FileUtils.mkdir_p(img_dir)

      paths = urls.each_with_index.filter_map do |url, idx|
        download_one(url, img_dir, idx + 1)
      end

      Result.new(paths: paths, errors: @errors)
    end

    private

    def download_one(url, img_dir, n)
      return nil if url.blank?

      data = @fetcher.call(url)
      if data.blank?
        @errors << "Foto #{n}: risposta vuota"
        return nil
      end

      filename = "photo_#{n}.jpg"
      File.binwrite(File.join(img_dir, filename), data)
      "img/#{filename}"
    rescue OpenURI::HTTPError => e
      @errors << "Foto #{n} HTTP error: #{e.message}"
      nil
    rescue => e
      @errors << "Foto #{n} download fallito: #{e.message}"
      nil
    end

    def default_fetch(url)
      URI.open(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, &:read)
    end

    def demo_directory
      File.join(storage_base, @demo.subdomain)
    end

    def storage_base
      ENV.fetch("DEMO_STORAGE_PATH", Rails.root.join("storage", "demos").to_s)
    end
  end
end
