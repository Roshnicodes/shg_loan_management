class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    loans = dashboard_loans
    shgs = dashboard_shgs(loans)
    visits = dashboard_visits(shgs)
    emis = ShgLoanEmi.where(shg_loan_id: loans.select(:id))
    year_loans = dashboard_year_loans(loans)

    @summary_counts = {
      "SHG Total" => loans.select(:shg_id).distinct.count,
      "SHG Members" => loans.select(:shg_member_id).count,
      "Total Loan" => helpers.number_to_currency(loans.sum(:principal_amount), unit: "₹"),
      "Collection" => helpers.number_to_currency(emis.sum(:paid_amount), unit: "₹")
    }

    @shg_approval_counts = approval_counts_for(shgs)
    @visit_approval_counts = approval_counts_for(visits)
    @recent_loans = loans.includes(:shg, :shg_member, :loan_status).order(created_at: :desc).limit(8)
    @dashboard_year_options = dashboard_year_options(loans)
    @dashboard_year = selected_dashboard_year(@dashboard_year_options)
    @yearly_analytics = yearly_analytics_for(year_loans)
  end

  private

  def dashboard_loans
    return crp_visible_loan_scope.where(active: true) if current_user&.crp?

    visible_shg_loans.where(active: true)
  end

  def dashboard_shgs(loans)
    return Shg.where(active: true, id: loans.select(:shg_id)) if current_user&.crp?

    visible_shgs.where(active: true)
  end

  def dashboard_visits(shgs)
    return visible_visit_records.where(active: true, shg_id: shgs.select(:id)) if current_user&.crp?

    visible_visit_records.where(active: true)
  end

  def approval_counts_for(relation)
    table_name = relation.klass.table_name
    returned = relation.where("LOWER(COALESCE(#{table_name}.approval_remarks, '')) LIKE ?", "%returned%")
    counts = relation.group(:approval_status).count

    {
      "Pending at DC" => counts.fetch("pending_dc", 0) - returned.where(approval_status: "pending_dc").count,
      "Pending at Assistant Admin" => counts.fetch("pending_assistant", 0),
      "Approved" => counts.fetch("approved", 0),
      "Rejected" => counts.fetch("rejected", 0),
      "Returned" => returned.count
    }
  end

  def selected_dashboard_year(years)
    requested = params[:year].to_s
    return "all" if requested == "all"

    requested.presence_in(years.map(&:to_s)) || years.first&.to_s || Date.current.year.to_s
  end

  def dashboard_year_options(loans)
    financial_years = loans
      .where.not(distribution_date: nil)
      .distinct
      .pluck(Arel.sql("CASE WHEN EXTRACT(MONTH FROM distribution_date)::int >= 4 THEN EXTRACT(YEAR FROM distribution_date)::int ELSE EXTRACT(YEAR FROM distribution_date)::int - 1 END"))
      .compact
      .map(&:to_i)
      .sort
      .reverse

    financial_years.presence || [ current_financial_year_start ]
  end

  def dashboard_year_loans(loans)
    @dashboard_year_options = dashboard_year_options(loans)
    @dashboard_year = selected_dashboard_year(@dashboard_year_options)
    return loans if @dashboard_year == "all"

    financial_year_start = @dashboard_year.to_i
    loans.where(distribution_date: Date.new(financial_year_start, 4, 1)..Date.new(financial_year_start + 1, 3, 31))
  end

  def yearly_analytics_for(loans)
    month_labels = financial_year_month_labels
    loan_counts = monthly_counts(loans)
    principal_amounts = monthly_sums(loans, :principal_amount)
    collections = monthly_collections(loans)

    {
      month_labels: month_labels,
      loan_counts: loan_counts,
      principal_amounts: principal_amounts,
      collections: collections,
      max_loan_count: [ loan_counts.max.to_i, 1 ].max,
      max_amount: [ principal_amounts.max.to_d, collections.max.to_d, 1.to_d ].max,
      totals: {
        loans: loans.count,
        shgs: loans.select(:shg_id).distinct.count,
        principal: loans.sum(:principal_amount),
        collection: total_collection(loans)
      },
      statuses: dashboard_status_counts(loans),
      products: dashboard_product_counts(loans)
    }
  end

  def month_expression
    Arel.sql("EXTRACT(MONTH FROM distribution_date)::int")
  end

  def financial_year_months
    [ 4, 5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 3 ]
  end

  def financial_year_month_labels
    financial_year_months.map { |month| Date::ABBR_MONTHNAMES[month] }
  end

  def current_financial_year_start
    today = Date.current
    today.month >= 4 ? today.year : today.year - 1
  end

  def monthly_counts(loans)
    counts = loans.group(month_expression).count
    financial_year_months.map { |month| counts[month].to_i }
  end

  def monthly_sums(loans, column)
    sums = loans.group(month_expression).sum(column)
    financial_year_months.map { |month| sums[month].to_d }
  end

  def monthly_collections(loans)
    imported = loans.where.not(source_paid: nil).group(month_expression).sum(:source_paid)
    regular = ShgLoanEmi
      .joins(:shg_loan)
      .where(shg_loans: { id: loans.where(source_paid: nil).select(:id) })
      .group(Arel.sql("EXTRACT(MONTH FROM shg_loans.distribution_date)::int"))
      .sum(:paid_amount)

    financial_year_months.map { |month| imported[month].to_d + regular[month].to_d }
  end

  def total_collection(loans)
    imported = loans.where.not(source_paid: nil).sum(:source_paid)
    regular = ShgLoanEmi.where(shg_loan_id: loans.where(source_paid: nil).select(:id)).sum(:paid_amount)

    imported + regular
  end

  def dashboard_status_counts(loans)
    loans
      .joins(:loan_status)
      .group(Arel.sql("COALESCE(NULLIF(shg_loans.source_loan_status, ''), loan_statuses.name)"))
      .count
      .sort_by { |_, count| -count }
      .first(5)
  end

  def dashboard_product_counts(loans)
    loans
      .joins(:product)
      .group("products.name")
      .count
      .sort_by { |_, count| -count }
      .first(5)
  end
end
