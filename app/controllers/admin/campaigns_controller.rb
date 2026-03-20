class Admin::CampaignsController < Admin::BaseController
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :toggle_active]

  def index
    @campaigns = Campaign.ordered
    @stats = {
      total:  Campaign.count,
      active: Campaign.active.count,
      companies_total: Company.kept.where.not(campaign_id: nil).count
    }
  end

  def show
    @companies = @campaign.companies.kept.order(created_at: :desc).limit(10)
    @stats = {
      total:     @campaign.companies.kept.count,
      contacted: @campaign.companies.kept.where(status: "contacted").count,
      converted: @campaign.companies.kept.where(status: "converted").count
    }
  end

  def new
    @campaign = Campaign.new(
      discovery_source: "google_places",
      use_demo:         false,
      use_ai_content:   true
    )
  end

  def create
    @campaign = Campaign.new(campaign_params)
    @campaign.user = current_user

    if @campaign.save
      redirect_to admin_campaign_path(@campaign),
                  notice: "Campagna '#{@campaign.name}' creata con successo."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to admin_campaign_path(@campaign),
                  notice: "Campagna aggiornata."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to admin_campaigns_path,
                notice: "Campagna '#{@campaign.name}' eliminata."
  end

  # POST /admin/campaigns/:id/toggle_active
  def toggle_active
    @campaign.update!(active: !@campaign.active)
    state = @campaign.active? ? "attivata" : "disattivata"
    redirect_to admin_campaigns_path, notice: "Campagna #{state}."
  end

  private

  def set_campaign
    @campaign = Campaign.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :description,
      :operator_profile, :target_profile,
      :discovery_source, :discovery_query,
      :email_subject_template, :email_body_template,
      :use_demo, :use_ai_content, :active
    )
  end
end
