class DashboardController < ApplicationController
  def index
    # ── Stats Web Agency (company senza campagna) ────────────────────────────
    wa_companies = Company.kept.where(campaign_id: nil)
    @web_agency = {
      total:     wa_companies.count,
      contacted: wa_companies.where(status: "contacted").count,
      converted: wa_companies.where(status: "converted").count,
      demos:     Demo.joins(:company).where(companies: { campaign_id: nil }).deployed.count,
      leads_sent: Lead.joins(:company).where(companies: { campaign_id: nil }).sent.count
    }

    # ── Stats Outreach (company con campagna) ────────────────────────────────
    out_companies = Company.kept.where.not(campaign_id: nil)
    @outreach = {
      campaigns:  Campaign.active.count,
      prospects:  out_companies.count,
      contacted:  out_companies.where(status: "contacted").count,
      converted:  out_companies.where(status: "converted").count,
      leads_sent: Lead.joins(:company).where.not(companies: { campaign_id: nil }).sent.count
    }

    # ── Attività recente (condivisa) ─────────────────────────────────────────
    @recent_leads = Lead.includes(:company, :demo)
                        .order(updated_at: :desc)
                        .limit(6)
  end
end
