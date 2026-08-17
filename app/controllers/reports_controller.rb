require "csv"

class ReportsController < ApplicationController
  helper_method :can_filter_report_state_district_user?, :report_loan_status,
    :report_collection_status,
    :show_report_state_filter?, :show_report_district_filter?, :show_report_block_filter?,
    :show_report_village_filter?, :show_report_user_filter?

  before_action :authenticate_user!

  def index
    set_selected_report_filters
    set_filter_options
    @report_ready = report_requested?
    @report_loans = @report_ready ? report_loans : ShgLoan.none
    @loans = @report_ready ? paginate_relation(@report_loans.order(distribution_date: :desc, id: :desc), per_page: 50) : []
    @loan_amounts = @report_ready ? loan_amounts_for(@loans) : {}
  end

  def export
    set_selected_report_filters
    loans = report_loans.order(distribution_date: :desc, id: :desc)
    amounts = loan_amounts_for(loans)

    stream_csv("loan-report-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "State", "District", "Block", "Village", "CRP", "SHG / ID / Village", "Member", "Loan No",
        "Product", "Disbursement Date", "Loan Status", "Collection Status", "Principal", "Total Payable",
        "Paid Amount", "Pending Amount", "Paid Installments", "Pending Installments", "Mobile"
      ])

      loans.find_each(batch_size: 1_000) do |loan|
        amount = amounts.fetch(loan.id, {})
        stream << CSV.generate_line([
          loan.shg.state.name,
          loan.shg.district.name,
          loan.shg.block.name,
          loan.shg.village.name,
          loan.source_crp_name.presence || loan.created_by&.name,
          loan.shg.display_name,
          loan.shg_member.name,
          loan.shg_member.loan_no,
          loan.product.name,
          loan.distribution_date,
          report_loan_status(loan, amount),
          report_collection_status(amount),
          loan.principal_amount,
          amount[:total_payable],
          amount[:paid_amount],
          amount[:pending_amount],
          amount[:paid_installments],
          amount[:pending_installments],
          loan.shg_member.mobile
        ])
      end
    end
  end

  private

  def can_filter_report_state_district_user?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def show_report_state_filter?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def show_report_district_filter?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def show_report_block_filter?
    current_user&.admin? || current_user&.assistant_admin? || current_user&.district_coordinator?
  end

  def show_report_village_filter?
    true
  end

  def show_report_user_filter?
    current_user&.admin? || current_user&.assistant_admin? || current_user&.district_coordinator?
  end

  def set_filter_options
    @states = limited_filter_records(filter_states, @selected_state_id)
    @districts = limited_filter_records(report_option_districts, @selected_district_id)
    @blocks = limited_filter_records(report_option_blocks, @selected_block_id)
    @villages = limited_filter_records(report_option_villages, @selected_village_id, limit: 5_000)
    @crps = limited_user_filter_records(report_option_crps, @selected_user_id)
    @shgs = limited_filter_records(report_option_shgs, @selected_shg_id, limit: 10_000)
    @members = limited_filter_records(report_option_members, @selected_member_id, limit: 1_000)
    @loan_filter_records = limited_filter_records(report_option_loans, @selected_loan_id, limit: 1_000)
    @loan_statuses = LoanStatus.order(:name)
    @shg_user_ids_by_id = report_shg_user_ids(@shgs)
    @member_user_ids_by_id = report_member_user_ids(@members)
    @loan_user_ids_by_id = report_loan_user_ids(@loan_filter_records)
  end

  def set_selected_report_filters
    @selected_state_id = selected_report_state_id
    @selected_district_id = selected_report_district_id
    @selected_block_id = selected_report_block_id
    @selected_village_id = selected_report_village_id
    @selected_user = selected_report_user
    @selected_user_id = @selected_user&.id
    @selected_shg_id = selected_report_shg_id
    @selected_member_id = selected_report_member_id
    @selected_loan_id = selected_report_loan_id
  end

  def report_option_districts
    districts = filter_districts
    districts = districts.where(state_id: @selected_state_id) if @selected_state_id.present?
    districts.order(:name)
  end

  def report_option_blocks
    blocks = filter_blocks
    blocks = blocks.joins(:district).where(districts: { state_id: @selected_state_id }) if @selected_state_id.present?
    blocks = blocks.where(district_id: @selected_district_id) if @selected_district_id.present?
    blocks.order(:name)
  end

  def report_option_villages
    villages = filter_villages
    if @selected_block_id.present?
      villages = villages.where(block_id: @selected_block_id)
    elsif @selected_district_id.present?
      villages = villages.joins(:block).where(blocks: { district_id: @selected_district_id })
    elsif @selected_state_id.present?
      villages = villages.joins(block: :district).where(districts: { state_id: @selected_state_id })
    end
    villages = villages.where(id: report_user_loan_scope.joins(:shg).select("shgs.village_id")) if @selected_user
    villages.order(:name)
  end

  def report_option_shgs
    return Shg.none unless @selected_village_id.present? || @selected_user.present? || params[:shg_id].present?

    shgs = visible_shgs.where(active: true, id: report_option_loan_scope.select(:shg_id))
    shgs.order(:name)
  end

  def report_option_members
    return ShgMember.none unless @selected_shg_id.present? || params[:member_id].present?

    members = visible_shg_members.where(active: true, id: report_option_loan_scope.select(:shg_member_id))
    members.order(:name)
  end

  def report_option_loans
    return ShgLoan.none unless @selected_member_id.present? || params[:loan_id].present?

    loans = report_option_loan_scope.includes(:shg_member, :shg)
    loans = loans.where(shg_member_id: @selected_member_id) if @selected_member_id.present?
    loans.order(distribution_date: :desc, id: :desc)
  end

  def report_option_crps
    return User.where(id: current_user.id).includes(:user_type).order(:name) if current_user&.crp?

    users = users_with_role_codes("CRP")
    users =
      if current_user&.admin? || current_user&.assistant_admin?
        users.to_a
      else
        visible_district_ids = visible_districts.pluck(:id)
        visible_block_ids = visible_blocks.pluck(:id)
        visible_village_ids = visible_villages.pluck(:id)
        users.to_a.select do |user|
          (user.office_district_ids & visible_district_ids).present? ||
            (user.office_block_ids & visible_block_ids).present? ||
            (user.office_village_ids & visible_village_ids).present?
        end
      end

    return users unless report_location_filter_selected?

    user_ids = report_user_ids_for_loans(report_location_loan_scope.includes(:created_by).to_a)
    users.select { |user| user_ids.include?(user.id) }
  end

  def report_loans
    loans = visible_shg_loans
      .where(active: true)
      .includes(:product, :loan_status, :created_by, :shg_member, shg: [ :state, :district, :block, :village ])

    loans = loans.where(distribution_date: params[:date_from]..) if params[:date_from].present?
    loans = loans.where(distribution_date: ..params[:date_to]) if params[:date_to].present?
    loans = loans.joins(:shg).where(shgs: { state_id: @selected_state_id }) if @selected_state_id.present?
    loans = loans.joins(:shg).where(shgs: { district_id: @selected_district_id }) if @selected_district_id.present?
    loans = loans.joins(:shg).where(shgs: { block_id: @selected_block_id }) if @selected_block_id.present?
    loans = loans.joins(:shg).where(shgs: { village_id: @selected_village_id }) if @selected_village_id.present?
    loans = loans.where(shg_id: @selected_shg_id) if @selected_shg_id.present?
    loans = loans.where(shg_member_id: @selected_member_id) if @selected_member_id.present?
    loans = loans.where(id: @selected_loan_id) if @selected_loan_id.present?
    loans = loans.where(loan_status_id: params[:loan_status_id]) if params[:loan_status_id].present?
    loans = apply_report_user_filter(loans)
    loans = apply_report_collection_filter(loans)
    search_report_loans(loans)
  end

  def report_requested?
    return false if params[:refresh_filters].present?

    params[:commit].present? ||
      params[:q].present? ||
      params[:page].present?
  end

  def selected_report_state_id
    return unless show_report_state_filter? && params[:state_id].present?

    filter_states.find_by(id: params[:state_id])&.id
  end

  def selected_report_district_id
    return unless show_report_district_filter? && params[:district_id].present?

    report_option_districts.find_by(id: params[:district_id])&.id
  end

  def selected_report_block_id
    return unless show_report_block_filter? && params[:block_id].present?

    report_option_blocks.find_by(id: params[:block_id])&.id
  end

  def selected_report_user
    return if params[:user_id].blank?

    report_option_crps.find { |user| user.id.to_s == params[:user_id].to_s }
  end

  def selected_report_village_id
    return if params[:village_id].blank?

    village = report_option_villages.find_by(id: params[:village_id])
    village&.id
  end

  def selected_report_shg_id
    return if params[:shg_id].blank?

    shg = visible_shgs.find_by(id: params[:shg_id])
    return unless shg
    return if @selected_state_id.present? && shg.state_id != @selected_state_id
    return if @selected_district_id.present? && shg.district_id != @selected_district_id
    return if @selected_block_id.present? && shg.block_id != @selected_block_id
    return if @selected_village_id.present? && shg.village_id != @selected_village_id
    return if @selected_user && !report_user_loan_scope.where(shg_id: shg.id).exists?

    shg.id
  end

  def selected_report_member_id
    return if params[:member_id].blank?

    member = visible_shg_members.includes(shg: :village).find_by(id: params[:member_id])
    return unless member
    return if @selected_shg_id.present? && member.shg_id != @selected_shg_id
    return if @selected_state_id.present? && member.shg.state_id != @selected_state_id
    return if @selected_district_id.present? && member.shg.district_id != @selected_district_id
    return if @selected_block_id.present? && member.shg.block_id != @selected_block_id
    return if @selected_village_id.present? && member.shg.village_id != @selected_village_id
    return if @selected_user && !report_user_loan_scope.where(shg_member_id: member.id).exists?

    member.id
  end

  def selected_report_loan_id
    return if params[:loan_id].blank?

    report_option_loans.find_by(id: params[:loan_id])&.id
  end

  def apply_report_user_filter(loans)
    return loans unless @selected_user

    user_filtered_loans(loans, @selected_user)
  end

  def report_user_loan_scope
    user_filtered_loans(visible_shg_loans.where(active: true), @selected_user)
  end

  def report_location_loan_scope
    loans = visible_shg_loans.where(active: true)
    loans = loans.joins(:shg).where(shgs: { state_id: @selected_state_id }) if @selected_state_id.present?
    loans = loans.joins(:shg).where(shgs: { district_id: @selected_district_id }) if @selected_district_id.present?
    loans = loans.joins(:shg).where(shgs: { block_id: @selected_block_id }) if @selected_block_id.present?
    loans = loans.joins(:shg).where(shgs: { village_id: @selected_village_id }) if @selected_village_id.present?
    loans
  end

  def report_option_loan_scope
    loans = report_location_loan_scope
    loans = loans.where(shg_id: @selected_shg_id) if @selected_shg_id.present?
    loans = user_filtered_loans(loans, @selected_user) if @selected_user
    loans
  end

  def report_location_filter_selected?
    @selected_state_id.present? || @selected_district_id.present? || @selected_block_id.present? || @selected_village_id.present?
  end

  def user_filtered_loans(loans, user)
    loans.where(created_by_id: user.id)
      .or(loans.where("LOWER(shg_loans.source_crp_identifier) = ?", user.login_id.to_s.downcase))
  end

  def apply_report_collection_filter(loans)
    return loans if params[:collection_status].blank?

    amounts = loan_amounts_for(loans)
    ids = amounts.filter_map do |loan_id, amount|
      case params[:collection_status]
      when "closed"
        loan_id if amount[:pending_amount].to_d <= 0
      when "pending"
        loan_id if amount[:pending_amount].to_d.positive?
      when "paid_installment", "paid_any"
        loan_id if amount[:paid_amount].to_d.positive?
      end
    end

    loans.where(id: ids)
  end

  def search_report_loans(loans)
    query = report_search_query
    return loans if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    loans.left_joins(:product, :created_by, :shg_member, shg: [ :state, :district, :block, :village ])
      .where(
        [
          "LOWER(shgs.name) LIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(shg_members.loan_no) LIKE :query",
          "LOWER(products.name) LIKE :query",
          "LOWER(states.name) LIKE :query",
          "LOWER(districts.name) LIKE :query",
          "LOWER(blocks.name) LIKE :query",
          "LOWER(villages.name) LIKE :query",
          "LOWER(users.name) LIKE :query",
          "LOWER(shg_loans.source_crp_name) LIKE :query",
          "LOWER(shg_loans.source_crp_identifier) LIKE :query"
        ].join(" OR "),
        query: pattern
      ).distinct
  end

  def report_search_query
    return "" if params[:commit].to_s.casecmp?("apply")

    params[:q].to_s.strip
  end

  def loan_amounts_for(loans)
    ids = loans.respond_to?(:pluck) ? loans.pluck(:id) : loans.map(&:id)
    return {} if ids.blank?

    emi_totals = ShgLoanEmi.where(shg_loan_id: ids)
      .group(:shg_loan_id)
      .pluck(
        :shg_loan_id,
        Arel.sql("SUM(paid_amount)"),
        Arel.sql("COUNT(*) FILTER (WHERE paid_amount >= due_amount)"),
        Arel.sql("COUNT(*) FILTER (WHERE paid_amount < due_amount)")
      )
      .to_h { |loan_id, paid, paid_installments, pending_installments| [ loan_id, { emi_paid: paid.to_d, paid_installments: paid_installments.to_i, pending_installments: pending_installments.to_i } ] }

    ShgLoan.where(id: ids).pluck(:id, :source_total_payable, :total_payable, :source_paid, :source_remaining).to_h do |id, source_total, total, source_paid, source_remaining|
      total_payable = source_total.presence || total.to_d
      paid_amount = source_paid.presence || emi_totals.dig(id, :emi_paid).to_d
      pending_amount = source_remaining.presence || (total_payable.to_d - paid_amount.to_d)
      [
        id,
        {
          total_payable: total_payable.to_d,
          paid_amount: paid_amount.to_d,
          pending_amount: pending_amount.to_d,
          paid_installments: emi_totals.dig(id, :paid_installments).to_i,
          pending_installments: emi_totals.dig(id, :pending_installments).to_i
        }
      ]
    end
  end

  def report_loan_status(loan, amount)
    return "Closed" if amount[:pending_amount].to_d <= 0

    loan.source_loan_status.presence || loan.loan_status.name
  end

  def report_collection_status(amount)
    return "Closed" if amount[:pending_amount].to_d <= 0
    return "Paid Installment" if amount[:paid_amount].to_d.positive?

    "Pending"
  end

  def report_shg_user_ids(shgs)
    shg_ids = shgs.map(&:id)
    return {} if shg_ids.blank?

    visible_shg_loans.where(active: true, shg_id: shg_ids)
      .includes(:created_by)
      .group_by(&:shg_id)
      .transform_values { |loans| report_user_ids_for_loans(loans) }
  end

  def report_member_user_ids(members)
    member_ids = members.map(&:id)
    return {} if member_ids.blank?

    visible_shg_loans.where(active: true, shg_member_id: member_ids)
      .includes(:created_by)
      .group_by(&:shg_member_id)
      .transform_values { |loans| report_user_ids_for_loans(loans) }
  end

  def report_loan_user_ids(loans)
    loans.map { |loan| [ loan.id, report_user_ids_for_loans([ loan ]) ] }.to_h
  end

  def report_user_ids_for_loans(loans)
    identifiers = loans.map { |loan| loan.source_crp_identifier.to_s.downcase }.compact_blank
    user_ids = loans.map(&:created_by_id).compact
    user_ids += User.where("LOWER(login_id) IN (?)", identifiers).pluck(:id) if identifiers.present?
    user_ids.uniq
  end
end
