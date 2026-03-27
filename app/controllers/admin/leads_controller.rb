# app/controllers/admin/leads_controller.rb
class Admin::LeadsController < Admin::BaseController
  PER_PAGE = 30

  def index
    base = Lead.includes(:company, :demo, :email_events)
               .order(created_at: :desc)
               .then { |q| filter_by_outcome(q) }
               .then { |q| filter_by_opened(q) }
               .then { |q| filter_by_clicked(q) }

    @total_count  = base.count
    @current_page = [params[:page].to_i, 1].max
    @total_pages  = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @current_page = [@current_page, @total_pages].min

    @leads = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)

    @stats = {
      total:    Lead.count,
      sent:     Lead.sent.count,
      opened:   Lead.opened.count,
      clicked:  Lead.clicked.count,
      opted_out: Lead.where(outcome: "opted_out").count,
      converted: Lead.where(outcome: "converted").count
    }
  end

  def show
    @lead    = Lead.includes(:company, :demo, :email_events).find(params[:id])
    @company = @lead.company
    @demo    = @lead.demo
    @events  = @lead.email_events.order(occurred_at: :asc)
  end

  private

  def filter_by_outcome(scope)
    params[:outcome].present? ? scope.where(outcome: params[:outcome]) : scope
  end

  def filter_by_opened(scope)
    params[:opened] == "1" ? scope.opened : scope
  end

  def filter_by_clicked(scope)
    params[:clicked] == "1" ? scope.clicked : scope
  end
end
