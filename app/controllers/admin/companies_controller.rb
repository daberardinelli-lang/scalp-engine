class Admin::CompaniesController < Admin::BaseController
  before_action :set_company, only: [:show, :enrich, :generate_content, :build_demo, :send_email, :mark_replied, :mark_converted, :update_contact, :restore_email]

  PER_PAGE = 25

  def index
    base = Company.kept
                  .order(created_at: :desc)
                  .then { |q| filter_by_status(q) }
                  .then { |q| filter_by_category(q) }
                  .then { |q| filter_by_search(q) }

    @total_count = base.count
    @current_page = [params[:page].to_i, 1].max
    @total_pages  = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @current_page = [@current_page, @total_pages].min

    @companies = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)

    @stats = {
      total:       Company.kept.count,
      discovered:  Company.kept.where(status: "discovered").count,
      enriched:    Company.kept.where(status: "enriched").count,
      demo_built:  Company.kept.where(status: "demo_built").count,
      contacted:   Company.kept.where(status: "contacted").count,
      converted:   Company.kept.where(status: "converted").count
    }
  end

  def show
  end

  # POST /admin/companies/discover
  def discover
    location    = params[:location].to_s.strip
    radius      = params[:radius].to_i.clamp(1_000, 50_000)
    campaign_id = params[:campaign_id].presence

    if location.blank?
      return redirect_to admin_companies_path,
                         alert: "Inserisci una location (es: Prato, Italia)"
    end

    if campaign_id.present?
      # Modalità Campaign: query libera
      campaign = Campaign.find_by(id: campaign_id)
      return redirect_to admin_companies_path, alert: "Campagna non trovata." unless campaign

      DiscoveryJob.perform_later(
        campaign_id: campaign.id,
        location:    location,
        radius:      radius
      )

      redirect_to admin_companies_path,
                  notice: "Discovery avviata per campagna '#{campaign.name}' in '#{location}' (raggio #{radius / 1000} km)."
    else
      # Modalità classica: categoria fissa
      category = params[:category].to_s

      unless Company::CATEGORIES.include?(category)
        return redirect_to admin_companies_path,
                           alert: "Categoria non valida: #{category}"
      end

      DiscoveryJob.perform_later(
        category: category,
        location: location,
        radius:   radius
      )

      redirect_to admin_companies_path,
                  notice: "Discovery avviata per '#{category}' in '#{location}' (raggio #{radius / 1000} km). " \
                          "I risultati appariranno entro qualche minuto."
    end
  end

  # POST /admin/companies/:id/enrich
  def enrich
    unless @company.status == "discovered"
      return redirect_to admin_company_path(@company),
                         alert: "Solo le aziende in stato 'discovered' possono essere arricchite."
    end

    EnrichmentJob.perform_later(company_id: @company.id)

    redirect_to admin_company_path(@company),
                notice: "Arricchimento avviato per '#{@company.name}'. Ricarica tra qualche minuto."
  end

  # POST /admin/companies/batch_enrich
  def batch_enrich
    count = Company.kept.where(status: "discovered").count

    if count.zero?
      return redirect_to admin_companies_path,
                         alert: "Nessuna azienda in stato 'discovered' da arricchire."
    end

    EnrichmentJob.perform_later   # senza company_id → batch

    redirect_to admin_companies_path,
                notice: "Batch enrichment avviato per #{count} aziende. I risultati appariranno progressivamente."
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
      return redirect_to admin_companies_path,
                         alert: "Nessuna azienda in stato 'enriched' da processare."
    end

    ContentGenerationJob.perform_later   # senza company_id → batch

    redirect_to admin_companies_path,
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
      return redirect_to admin_companies_path,
                         alert: "Nessuna azienda con contenuti AI pronti da buildare."
    end

    DemoBuildJob.perform_later   # senza company_id → batch

    redirect_to admin_companies_path,
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
      return redirect_to admin_companies_path,
                         alert: "Nessuna azienda pronta per l'invio (demo deployata + email trovata + non opted-out)."
    end

    scope.find_each do |company|
      OutreachEmailJob.perform_later(company_id: company.id)
    end

    redirect_to admin_companies_path,
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

  def set_company
    @company = Company.kept.find(params[:id])
  end

  def contact_params
    params.require(:company).permit(:email, :email_status, :notes, :original_email)
  end

  def filter_by_status(scope)
    params[:status].present? ? scope.where(status: params[:status]) : scope
  end

  def filter_by_category(scope)
    params[:category].present? ? scope.where(category: params[:category]) : scope
  end

  def filter_by_search(scope)
    return scope if params[:q].blank?

    q = "%#{params[:q]}%"
    scope.where("name ILIKE ? OR city ILIKE ? OR province ILIKE ?", q, q, q)
  end
end
