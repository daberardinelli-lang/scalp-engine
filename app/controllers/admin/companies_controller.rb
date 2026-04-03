class Admin::CompaniesController < Admin::BaseController
  before_action :set_company, only: [:show, :enrich, :generate_content, :build_demo, :send_email, :mark_replied, :mark_converted, :update_contact, :restore_email]

  PER_PAGE = 25

  # GET /admin/contatti — sezione Contatti (outreach/campagne)
  def contatti
    @mode = "outreach"
    load_companies_list
    render :contatti
  end

  # GET /admin/software-agency — sezione Software Agency (demo siti)
  def software_agency
    @mode = "web_agency"
    load_companies_list
    render :software_agency
  end

  def show
  end

  # POST /admin/companies/discover
  def discover
    location    = params[:location].to_s.strip
    radius      = params[:radius].to_i.clamp(1_000, 50_000)
    campaign_id = params[:campaign_id].presence

    if location.blank?
      return redirect_to list_path_for_mode,
                         alert: "Inserisci una location (es: Prato, Italia)"
    end

    if campaign_id.present?
      # Modalità Campaign: query libera
      campaign = Campaign.find_by(id: campaign_id)
      return redirect_to admin_contatti_path, alert: "Campagna non trovata." unless campaign

      DiscoveryJob.perform_later(
        campaign_id: campaign.id,
        location:    location,
        radius:      radius
      )

      redirect_to admin_contatti_path,
                  notice: "Ricerca avviata per campagna '#{campaign.name}' in '#{location}' (raggio #{radius / 1000} km)."
    else
      # Modalità classica: categoria fissa
      category = params[:category].to_s

      unless Company::CATEGORIES.include?(category)
        return redirect_to admin_software_agency_path,
                           alert: "Categoria non valida: #{category}"
      end

      DiscoveryJob.perform_later(
        category: category,
        location: location,
        radius:   radius
      )

      redirect_to admin_software_agency_path,
                  notice: "Ricerca avviata per '#{category}' in '#{location}' (raggio #{radius / 1000} km). " \
                          "I risultati appariranno entro qualche minuto."
    end
  end

  # POST /admin/companies/:id/enrich
  def enrich
    unless @company.status == "discovered"
      return redirect_to admin_company_path(@company),
                         alert: "Solo le aziende in stato 'discovered' possono essere arricchite."
    end

    enrich_mode = params[:enrich_mode].presence || "full"

    EnrichmentJob.perform_later(company_id: @company.id, enrich_mode: enrich_mode)

    label = enrich_mode == "email_only" ? "solo email" : "email + recensioni"
    redirect_to admin_company_path(@company),
                notice: "Arricchimento (#{label}) avviato per '#{@company.name}'. Ricarica tra qualche minuto."
  end

  # POST /admin/companies/batch_enrich
  def batch_enrich
    count = Company.kept.where(status: "discovered").count

    if count.zero?
      return redirect_to list_path_for_mode,
                         alert: "Nessuna azienda in stato 'discovered' da arricchire."
    end

    enrich_mode = params[:enrich_mode].presence || "full"

    EnrichmentJob.perform_later(enrich_mode: enrich_mode)

    label = enrich_mode == "email_only" ? "solo email" : "email + recensioni"
    redirect_to list_path_for_mode,
                notice: "Batch enrichment (#{label}) avviato per #{count} aziende. I risultati appariranno progressivamente."
  end

  # GET /admin/companies/export_xlsx
  def export_xlsx
    companies = Company.kept
                       .includes(:campaign)
                       .then { |q| filter_by_mode(q) }
                       .then { |q| filter_by_status(q) }
                       .then { |q| filter_by_campaign(q) }
                       .then { |q| filter_by_search(q) }
                       .order(:name)

    package = Axlsx::Package.new
    wb = package.workbook

    # Stili
    header_style = wb.styles.add_style(
      b: true, bg_color: "4472C4", fg_color: "FFFFFF",
      alignment: { horizontal: :center }, border: { style: :thin, color: "000000" }
    )
    cell_style = wb.styles.add_style(
      border: { style: :thin, color: "D9D9D9" },
      alignment: { vertical: :center, wrap_text: true }
    )

    wb.add_worksheet(name: "Aziende") do |sheet|
      sheet.add_row [
        "Nome", "Categoria", "Città", "Provincia", "Indirizzo", "Telefono",
        "Email", "Email Source", "Link WhatsApp", "Stato", "Rating", "N. Recensioni",
        "Ha sito web", "Campagna", "Data scoperta"
      ], style: header_style

      companies.find_each do |c|
        wa_url = c.phone.present? ? helpers.whatsapp_url_for(c) : ""
        sheet.add_row [
          c.name,
          c.category,
          c.city,
          c.province,
          c.address,
          c.phone,
          c.email,
          c.email_source,
          wa_url,
          c.status,
          c.maps_rating,
          c.maps_reviews_count,
          c.has_website ? "Sì" : "No",
          c.campaign&.name,
          c.created_at&.strftime("%d/%m/%Y %H:%M")
        ], style: cell_style
      end

      # Auto-larghezza colonne
      sheet.column_widths 35, 15, 15, 8, 25, 18, 30, 14, 12, 8, 12, 10, 20, 16, 16
    end

    send_data package.to_stream.read,
              filename: "aziende_#{Date.today.strftime('%Y%m%d')}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # POST /admin/companies/:id/generate_content
  def generate_content
    unless %w[enriched demo_built].include?(@company.status)
      return redirect_to admin_company_path(@company),
                         alert: "Solo le aziende in stato 'enriched' o 'demo_built' possono generare contenuti."
    end

    ContentGenerationJob.perform_later(company_id: @company.id)

    redirect_to admin_company_path(@company),
                notice: "Generazione contenuti AI avviata per '#{@company.name}'. Ricarica tra qualche minuto."
  end

  # POST /admin/companies/batch_generate
  def batch_generate
    count = Company.kept.where(status: "enriched").where(opted_out_at: nil).count

    if count.zero?
      return redirect_to list_path_for_mode,
                         alert: "Nessuna azienda in stato 'enriched' da processare."
    end

    ContentGenerationJob.perform_later   # senza company_id → batch

    redirect_to list_path_for_mode,
                notice: "Generazione batch AI avviata per #{count} aziende. I risultati appariranno progressivamente."
  end

  # POST /admin/companies/:id/build_demo
  def build_demo
    demo = @company.demo

    unless demo&.content_generated?
      return redirect_to admin_company_path(@company),
                         alert: "I contenuti AI non sono ancora stati generati. Genera prima i contenuti."
    end

    DemoBuildJob.perform_later(company_id: @company.id)

    redirect_to admin_company_path(@company),
                notice: "Build demo avviato per '#{@company.name}'. Ricarica tra qualche secondo."
  end

  # POST /admin/companies/batch_build
  def batch_build
    count = Company.kept
                   .where(status: "demo_built")
                   .where(opted_out_at: nil)
                   .joins(:demo)
                   .merge(Demo.where.not(generated_headline: [nil, ""]))
                   .count

    if count.zero?
      return redirect_to list_path_for_mode,
                         alert: "Nessuna azienda con contenuti AI pronti da buildare."
    end

    DemoBuildJob.perform_later   # senza company_id → batch

    redirect_to list_path_for_mode,
                notice: "Build batch demo avviato per #{count} aziende."
  end

  # POST /admin/companies/:id/send_email
  def send_email
    unless @company.contactable?
      return redirect_to admin_company_path(@company),
                         alert: "Azienda non contattabile: opted-out, ha un sito web o email mancante."
    end

    requires_demo = @company.campaign.nil? || @company.campaign.use_demo?
    if requires_demo && !@company.demo&.deployed?
      return redirect_to admin_company_path(@company),
                         alert: "La demo HTML non è ancora stata buildata. Avvia prima il Build Demo."
    end

    OutreachEmailJob.perform_later(company_id: @company.id)

    redirect_to admin_company_path(@company),
                notice: "Email outreach accodata per '#{@company.name}' <#{@company.email}>."
  end

  # POST /admin/companies/batch_email
  def batch_email
    scope = Company.contactable
                   .where(status: "demo_built")
                   .joins(:demo)
                   .merge(Demo.where.not(deployed_at: nil))

    count = scope.count

    if count.zero?
      return redirect_to list_path_for_mode,
                         alert: "Nessuna azienda pronta per l'invio (demo deployata + email trovata + non opted-out)."
    end

    scope.find_each do |company|
      OutreachEmailJob.perform_later(company_id: company.id)
    end

    redirect_to list_path_for_mode,
                notice: "Email batch accodata per #{count} aziende."
  end

  # PATCH /admin/companies/:id/update_contact
  def update_contact
    new_email = contact_params[:email].to_s.strip

    # Preserva la mail originale (trovata dal scraping) se viene sovrascritta per la prima volta
    if new_email.present? &&
       new_email != @company.email.to_s &&
       @company.original_email.blank? &&
       @company.email.present?
      @company.original_email = @company.email
    end

    if @company.update(contact_params)
      redirect_to admin_company_path(@company),
                  notice: "Contatti aggiornati."
    else
      redirect_to admin_company_path(@company),
                  alert: "Errore: #{@company.errors.full_messages.join(', ')}"
    end
  end

  # PATCH /admin/companies/:id/restore_email
  def restore_email
    if @company.original_email.blank?
      return redirect_to admin_company_path(@company),
                         alert: "Nessuna email originale da ripristinare."
    end

    @company.update!(email: @company.original_email, email_status: "found", original_email: nil)
    redirect_to admin_company_path(@company), notice: "Email originale ripristinata."
  end

  # POST /admin/companies/:id/mark_replied
  def mark_replied
    @company.update!(status: "replied")

    # Aggiorna anche il Lead più recente inviato
    lead = @company.lead
    if lead&.email_sent_at.present? && lead.replied_at.nil?
      lead.update!(replied_at: Time.current, outcome: "interested")
      EmailEvent.create!(lead: lead, event_type: "replied", occurred_at: Time.current)
    end

    redirect_to admin_company_path(@company), notice: "Azienda contrassegnata come: ha risposto."
  end

  # POST /admin/companies/:id/mark_converted
  def mark_converted
    @company.update!(status: "converted")

    # Aggiorna anche il Lead più recente inviato
    lead = @company.lead
    if lead&.email_sent_at.present?
      lead.update!(outcome: "converted")
    end

    redirect_to admin_company_path(@company), notice: "Azienda convertita in cliente."
  end

  private

  def load_companies_list
    base = Company.kept
                  .includes(:campaign)
                  .then { |q| filter_by_mode(q) }
                  .then { |q| filter_by_status(q) }
                  .then { |q| filter_by_category(q) }
                  .then { |q| filter_by_campaign(q) }
                  .then { |q| filter_by_search(q) }
                  .then { |q| filter_by_email(q) }
                  .then { |q| apply_sort(q) }

    @total_count = base.count
    @current_page = [params[:page].to_i, 1].max
    @total_pages  = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @current_page = [@current_page, @total_pages].min

    @companies = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)

    mode_base = mode_scope
    @stats = {
      total:       mode_base.count,
      discovered:  mode_base.where(status: "discovered").count,
      enriched:    mode_base.where(status: "enriched").count,
      demo_built:  mode_base.where(status: "demo_built").count,
      contacted:   mode_base.where(status: "contacted").count,
      replied:     mode_base.where(status: "replied").count,
      converted:   mode_base.where(status: "converted").count
    }
  end

  def list_path_for_mode
    case params[:mode].presence || @mode
    when "outreach"   then admin_contatti_path
    when "web_agency" then admin_software_agency_path
    else admin_contatti_path
    end
  end

  def set_company
    @company = Company.kept.find(params[:id])
  end

  def contact_params
    params.require(:company).permit(:email, :email_status, :notes, :original_email)
  end

  def mode_scope
    case @mode
    when "web_agency" then Company.kept.where(campaign_id: nil)
    when "outreach"   then Company.kept.where.not(campaign_id: nil)
    else Company.kept
    end
  end

  def filter_by_mode(scope)
    case @mode
    when "web_agency" then scope.where(campaign_id: nil)
    when "outreach"   then scope.where.not(campaign_id: nil)
    else scope
    end
  end

  def filter_by_status(scope)
    params[:status].present? ? scope.where(status: params[:status]) : scope
  end

  def filter_by_category(scope)
    params[:category].present? ? scope.where(category: params[:category]) : scope
  end

  def filter_by_campaign(scope)
    return scope if params[:campaign_id].blank?
    scope.where(campaign_id: params[:campaign_id])
  end

  def filter_by_search(scope)
    return scope if params[:q].blank?

    q = "%#{params[:q]}%"
    scope.where("name ILIKE ? OR city ILIKE ? OR province ILIKE ?", q, q, q)
  end

  SORTABLE_COLUMNS = %w[name city maps_rating maps_reviews_count created_at status].freeze

  def apply_sort(scope)
    col = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : "created_at"
    dir = params[:dir] == "asc" ? :asc : :desc
    # Per rating: metti i nil in fondo
    if col == "maps_rating"
      scope.order(Arel.sql("maps_rating IS NULL, maps_rating #{dir == :asc ? 'ASC' : 'DESC'}"))
    else
      scope.order(col => dir)
    end
  end

  def filter_by_email(scope)
    case params[:email_filter]
    when "found"   then scope.where.not(email: [nil, ""])
    when "missing" then scope.where(email: [nil, ""])
    else scope
    end
  end
end
