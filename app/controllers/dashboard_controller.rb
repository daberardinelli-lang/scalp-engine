class DashboardController < ApplicationController
  def index
    # ── Pipeline aziende ────────────────────────────────────────────────────
    @pipeline = Company::STATUSES.index_with do |status|
      Company.kept.where(status: status).count
    end
    @total_companies = Company.kept.count

    # ── Metriche email (ultimi 30 giorni) ───────────────────────────────────
    leads_sent = Lead.sent

    @email_stats = {
      total_sent:      leads_sent.count,
      sent_month:      leads_sent.where("email_sent_at >= ?", 30.days.ago).count,
      total_opened:    Lead.opened.count,
      total_clicked:   Lead.clicked.count,
      total_opted_out: Lead.where(outcome: "opted_out").count,
      open_rate:       rate(Lead.opened.count, leads_sent.count),
      click_rate:      rate(Lead.clicked.count, leads_sent.count)
    }

    # ── Demo deployate ──────────────────────────────────────────────────────
    @demos_deployed = Demo.deployed.count
    @total_views    = Demo.sum(:view_count)

    # ── Attività recente ────────────────────────────────────────────────────
    @recent_leads = Lead.includes(:company, :demo)
                        .order(updated_at: :desc)
                        .limit(8)

    # ── Conversioni ─────────────────────────────────────────────────────────
    @conversions = {
      contacted: Company.kept.where(status: "contacted").count,
      replied:   Company.kept.where(status: "replied").count,
      converted: Company.kept.where(status: "converted").count
    }
  end

  private

  def rate(numerator, denominator)
    return 0.0 if denominator.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end
end
