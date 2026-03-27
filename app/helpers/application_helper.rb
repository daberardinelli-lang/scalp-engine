module ApplicationHelper
  # Restituisce le classi Tailwind per il link nella navbar admin,
  # evidenziando il link attivo in base al controller corrente.
  def nav_link_class(section)
    active = controller_path.start_with?("admin/#{section}")
    if active
      "font-medium text-emerald-600"
    else
      "text-gray-600 hover:text-gray-900"
    end
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
