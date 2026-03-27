# app/controllers/admin/demos_controller.rb
class Admin::DemosController < Admin::BaseController
  PER_PAGE = 25

  def index
    base = Demo.includes(:company)
               .order(created_at: :desc)
               .then { |q| filter_by_deployed(q) }

    @total_count  = base.count
    @current_page = [params[:page].to_i, 1].max
    @total_pages  = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @current_page = [@current_page, @total_pages].min

    @demos = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)

    @stats = {
      total:    Demo.count,
      deployed: Demo.deployed.count,
      active:   Demo.active.count,
      expired:  Demo.expired.count,
      views:    Demo.sum(:view_count)
    }
  end

  def show
    @demo    = Demo.includes(:company, :leads).find(params[:id])
    @company = @demo.company
    @lead    = @demo.leads.order(created_at: :desc).first
  end

  private

  def filter_by_deployed(scope)
    case params[:filter]
    when "deployed" then scope.deployed
    when "not_deployed" then scope.where(deployed_at: nil)
    when "expired" then scope.expired
    else scope
    end
  end
end
