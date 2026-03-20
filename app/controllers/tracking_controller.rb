class TrackingController < ApplicationController
  skip_before_action :authenticate_user!
  skip_after_action  :verify_authorized, raise: false

  # GET /t/:token/open
  # Pixel di tracking — risponde con immagine 1x1 trasparente
  def open
    lead = Lead.find_by(tracking_token: params[:token])
    if lead && lead.email_opened_at.nil?
      lead.update!(email_opened_at: Time.current)
      lead.email_events.create!(
        event_type: "opened",
        occurred_at: Time.current,
        metadata: { ip: request.remote_ip, user_agent: request.user_agent }
      )
    end
    # Pixel 1x1 trasparente
    send_data tracking_pixel, type: "image/gif", disposition: "inline"
  end

  # GET /t/:token/click
  # Link di redirect verso la demo — traccia il click
  def click
    lead = Lead.find_by(tracking_token: params[:token])
    if lead
      lead.update!(link_clicked_at: Time.current) if lead.link_clicked_at.nil?
      lead.email_events.create!(
        event_type: "clicked",
        occurred_at: Time.current,
        metadata: { ip: request.remote_ip }
      )
      demo_url = "https://#{lead.demo.subdomain}.#{ENV.fetch("DEMO_BASE_DOMAIN", "demo.webradar.it")}"
      redirect_to demo_url, allow_other_host: true
    else
      redirect_to root_path
    end
  end

  # GET /t/:token/optout
  # Opt-out GDPR — annulla iscrizione e mostra conferma
  def opt_out
    lead = Lead.find_by(tracking_token: params[:token])
    if lead
      lead.update!(outcome: "opted_out")
      lead.company.update!(opted_out_at: Time.current, status: "opted_out")
      lead.email_events.create!(
        event_type: "opted_out",
        occurred_at: Time.current,
        metadata: { ip: request.remote_ip }
      )
    end
    render :opt_out_confirmed, layout: false
  end

  private

  def tracking_pixel
    # GIF 1x1 pixel trasparente (base64 decodificato)
    Base64.decode64(
      "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
    )
  end
end
