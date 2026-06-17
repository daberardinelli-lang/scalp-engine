# app/controllers/demo_previews_controller.rb
#
# Serve le demo HTML in ambiente di sviluppo/staging.
# In produzione, le demo sono servite direttamente da nginx via wildcard subdomain
# (*.demo.webradar.it → nginx → storage/demos/{subdomain}/index.html).
#
class DemoPreviewsController < ApplicationController
  skip_before_action :authenticate_user!
  # Serve solo contenuti statici pubblici (HTML/immagini/video demo): nessuna
  # azione stateful → disabilita CSRF e il blocco cross-origin sugli asset.
  skip_forgery_protection

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

    # Le foto sono salvate come path relativi (img/photo_N.jpg). In produzione
    # nginx le serve dalla root del subdomain; in preview le riscriviamo in path
    # assoluti serviti dalla action #image. Copre sia <img src> sia background-image.
    base = demo_preview_path(subdomain)
    html = html
           .gsub('="img/', %(="#{base}/img/))      # src="img/..." e poster="img/..."
           .gsub("url('img/", "url('#{base}/img/")

    render html: html.html_safe, layout: false
  rescue => e
    Rails.logger.error "[DemoPreviewsController] #{e.message}"
    render plain: "Errore interno", status: :internal_server_error
  end

  # Serve le immagini statiche della demo in sviluppo/staging.
  # In produzione le immagini sono servite direttamente da nginx.
  def image
    subdomain = params[:subdomain].to_s.strip
    filename  = params[:filename].to_s

    unless subdomain.match?(/\A[a-z0-9\-]+\z/) &&
           filename.match?(/\A[a-zA-Z0-9_\-]+\.(jpe?g|png|webp)\z/i)
      return head :bad_request
    end

    storage_base = File.expand_path(
      ENV.fetch("DEMO_STORAGE_PATH", Rails.root.join("storage", "demos").to_s)
    )
    path = File.expand_path(File.join(storage_base, subdomain, "img", filename))

    # Sicurezza: blocca path traversal fuori dalla directory di storage
    unless path.start_with?(storage_base + File::SEPARATOR) && File.exist?(path)
      return head :not_found
    end

    send_file path, disposition: "inline"
  rescue => e
    Rails.logger.error "[DemoPreviewsController#image] #{e.message}"
    head :internal_server_error
  end

  # Serve gli asset condivisi delle demo (clip video hero, ecc.) in sviluppo.
  # In produzione: nginx location /_assets/.
  ASSET_MIME = {
    ".mp4"  => "video/mp4",
    ".webm" => "video/webm",
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png"  => "image/png",
    ".webp" => "image/webp"
  }.freeze

  def asset
    rel = params[:path].to_s

    # Sicurezza: niente path traversal o path assoluti
    return head :bad_request if rel.blank? || rel.include?("..") || rel.start_with?("/")

    assets_root = File.expand_path(File.join(DemoBuilder::CategoryHeroScene.storage_base, "_assets"))
    path        = File.expand_path(File.join(assets_root, rel))

    unless path.start_with?(assets_root + File::SEPARATOR) && File.file?(path)
      return head :not_found
    end

    type = ASSET_MIME[File.extname(path).downcase] || "application/octet-stream"
    send_file path, type: type, disposition: "inline"
  rescue => e
    Rails.logger.error "[DemoPreviewsController#asset] #{e.message}"
    head :internal_server_error
  end
end
