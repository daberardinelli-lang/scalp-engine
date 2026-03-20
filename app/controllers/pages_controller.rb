# app/controllers/pages_controller.rb
#
# Pagine statiche pubbliche (no autenticazione richiesta).
#
class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  # GET /privacy
  def privacy
    @brand_name  = ENV.fetch("BRAND_NAME", "WebRadar")
    @brand_email = ENV.fetch("BRAND_EMAIL", "info@webradar.it")
  end
end
