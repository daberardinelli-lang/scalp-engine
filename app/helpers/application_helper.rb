module ApplicationHelper
  # Restituisce le classi Tailwind per il link nella navbar admin,
  # evidenziando il link attivo in base al controller corrente.
  def nav_link_class(section)
    active = case section
             when "contatti"
               controller_path == "admin/companies" && (params[:mode] == "outreach" || action_name == "contatti")
             when "software_agency"
               controller_path == "admin/companies" && (params[:mode] == "web_agency" || action_name == "software_agency")
             else
               controller_path.start_with?("admin/#{section}")
             end
    if active
      "font-medium text-emerald-600"
    else
      "text-gray-600 hover:text-gray-900"
    end
  end

  # Genera URL wa.me con messaggio precompilato per una Company
  def whatsapp_url_for(company, custom_message: nil)
    return "#" if company.phone.blank?

    # Normalizza il numero: rimuovi spazi, trattini, parentesi
    phone = company.phone.gsub(/[\s\-\(\)]+/, "")
    # Aggiungi prefisso italiano se manca
    phone = "39#{phone}" unless phone.start_with?("39") || phone.start_with?("+39")
    phone = phone.delete("+")

    message = custom_message || whatsapp_default_message(company)
    "https://wa.me/#{phone}?text=#{CGI.escape(message)}"
  end

  def whatsapp_default_message(company)
    brand = ENV.fetch("BRAND_NAME", "WebRadar")
    "Buongiorno, sono #{brand}.\n" \
    "Ho visto la vostra attivita \"#{company.name}\" su Google Maps " \
    "e avrei una proposta che potrebbe interessarvi.\n" \
    "Posso inviarvi i dettagli?"
  end

  # Badge colorato per lo status pipeline di un'azienda
  def status_badge(status)
    colors = {
      "discovered"  => "bg-gray-100 text-gray-700",
      "enriched"    => "bg-blue-100 text-blue-700",
      "demo_built"  => "bg-purple-100 text-purple-700",
      "contacted"   => "bg-yellow-100 text-yellow-700",
      "replied"     => "bg-orange-100 text-orange-700",
      "converted"   => "bg-emerald-100 text-emerald-700",
      "opted_out"   => "bg-red-100 text-red-700"
    }
    css = colors.fetch(status, "bg-gray-100 text-gray-700")
    content_tag(:span, status.humanize, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{css}")
  end
end
