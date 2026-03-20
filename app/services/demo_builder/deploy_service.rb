# app/services/demo_builder/deploy_service.rb
#
# Scrive l'HTML generato su disco e aggiorna il record Demo con html_path,
# deployed_at ed expires_at.
#
# Uso:
#   result = DemoBuilder::DeployService.call(demo: demo, html: html_string)
#   result.success? # => true
#   result.html_path # => "/path/to/storage/demos/nome-azienda-abc123/index.html"
#
module DemoBuilder
  class DeployService
    DEMO_VALIDITY_DAYS = 90

    Result = Struct.new(:demo, :html_path, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    def self.call(demo:, html:)
      new(demo: demo, html: html).call
    end

    def initialize(demo:, html:)
      @demo = demo
      @html = html
    end

    def call
      validate!
      html_path = write_html!
      update_demo!(html_path)

      Rails.logger.info "[DeployService] Demo deployed: #{@demo.subdomain} → #{html_path}"
      Result.new(demo: @demo, html_path: html_path, errors: [])
    rescue ArgumentError => e
      Result.new(demo: @demo, html_path: nil, errors: [e.message])
    rescue => e
      Rails.logger.error "[DeployService] Error for #{@demo.subdomain}: #{e.message}"
      Result.new(demo: @demo, html_path: nil, errors: ["Deploy error: #{e.message}"])
    end

    private

    def validate!
      raise ArgumentError, "Demo non valido"   if @demo.nil? || @demo.subdomain.blank?
      raise ArgumentError, "HTML vuoto o nil"  if @html.blank?
    end

    def write_html!
      dir       = demo_directory
      html_path = File.join(dir, "index.html")

      FileUtils.mkdir_p(dir)
      File.write(html_path, @html, encoding: "UTF-8")

      html_path
    end

    def update_demo!(html_path)
      @demo.update!(
        html_path:   html_path,
        deployed_at: Time.current,
        expires_at:  DEMO_VALIDITY_DAYS.days.from_now
      )
    end

    def demo_directory
      File.join(storage_base, @demo.subdomain)
    end

    def storage_base
      ENV.fetch("DEMO_STORAGE_PATH", Rails.root.join("storage", "demos").to_s)
    end
  end
end
