# app/controllers/demo_previews_controller.rb
#
# Serve le demo HTML in ambiente di sviluppo/staging.
# In produzione, le demo sono servite direttamente da nginx via wildcard subdomain
# (*.demo.webradar.it → nginx → storage/demos/{subdomain}/index.html).
#
class DemoPreviewsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    subdomain = params[:subdomain].to_s.strip

    if subdomain.blank? || subdomain !~ /\A[a-z0-9\-]+\z/
      return render plain: "Subdomain non valido", status: :bad_request
    end

    @demo = Demo.find_by(subdomain: subdomain)

    if @demo.nil?
      return render plain: "Demo non trovata (#{subdomain})", status: :not_found
    end

    unless @demo.html_path.present? && File.exist?(@demo.html_path)
      return render plain: "HTML non ancora generato per questa demo. " \
                           "Avvia il build dalla dashboard admin.", status: :not_found
    end

    # Sicurezza: verifica che il path sia dentro la directory di storage demo
    storage_base = File.expand_path(
      ENV.fetch("DEMO_STORAGE_PATH", Rails.root.join("storage", "demos").to_s)
    )
    resolved_path = File.expand_path(@demo.html_path)
    unless resolved_path.start_with?(storage_base + File::SEPARATOR)
      Rails.logger.error "[DemoPreviewsController] Path traversal bloccato: #{@demo.html_path}"
      return render plain: "Errore interno", status: :internal_server_error
    end

    # Registra la visualizzazione
    @demo.register_view!

    html = File.read(@demo.html_path, encoding: "UTF-8")
    render html: html.html_safe, layout: false
  rescue => e
    Rails.logger.error "[DemoPreviewsController] #{e.message}"
    render plain: "Errore interno", status: :internal_server_error
  end
end
