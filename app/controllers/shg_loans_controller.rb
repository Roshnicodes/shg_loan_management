require "csv"
require "fileutils"
require "nokogiri"
require "rexml/document"
require "set"
require "zip"

class ShgLoansController < ApplicationController
  helper_method :can_filter_loan_state_district_crp?

  LOAN_INDEX_PARAMS = %i[
    page q date_from date_to crp_id
    state_id district_id block_id village_id shg_id record_status
  ].freeze
  LOAN_PREFILL_PARAMS = %i[
    shg_id block_id village_id product_id geography_type distribution_date
    loan_term_type loan_term principal_amount interest_percent active
  ].freeze
  LOAN_PREFILL_SESSION_KEY = :shg_loan_prefill_params

  IMPORT_BATCH_SIZE = 2_000
  PLACEHOLDER_IMPORT_LOAN_VALUES = %w[ww].freeze
  ImportMemberReference = Struct.new(:id, :shg_id, :name, keyword_init: true)
  ImportShgReference = Struct.new(:id, :village_id, :name, :approved, keyword_init: true) do
    def approved? = approved
  end

  before_action :authenticate_user!
  before_action -> { restore_persistent_index_params(:shg_loans_index_params, :shg_loans_path, LOAN_INDEX_PARAMS) }, only: :index
  before_action :set_loan_form_prefill, only: %i[new create]
  before_action :set_loan, only: %i[show edit update destroy disable passbook update_product]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_shg_loan_manage_permission!, only: %i[edit update update_product]
  before_action :require_manage_permission!, only: %i[destroy disable]
  before_action :require_loan_import_permission!, only: %i[new_import import]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

  def index
    set_filter_options
    @loan_imports = LoanImport.includes(:user).order(created_at: :desc).limit(5) if can_import_loan_data?
    @loans = paginate_relation(loan_index_scope)
    @loan_emi_totals = emi_totals_by_loan_id(@loans.map(&:id))
    @loan_product_options = product_code_options
  end

  def export
    stream_loans_csv(loan_number_ordered_loans(filtered_loans(preload_emis: false)))
  end

  def loan_no_check_export
    stream_loan_no_check_csv(
      loan_number_ordered_loans(filtered_loans(preload_emis: false)),
      loan_number_ordered_members(filtered_stale_loan_no_members)
    )
  end

  def new_import
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS)
  end

  def import
    file = params[:file]
    return redirect_to(results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), alert: "Please select a CSV or Excel file.") unless file.present?

    loan_import = start_async_loan_import(file)
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), notice: "Loan import started in background."
  rescue CSV::MalformedCSVError, Zip::Error, REXML::ParseException
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), alert: "Uploaded file is not a valid CSV or Excel file."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), alert: e.record.errors.full_messages.to_sentence
  end

  def show
    @loan.ensure_emi_schedule!
  end

  def passbook
    @loan.ensure_emi_schedule!
    @emis = @loan.shg_loan_emis.order(:installment_no)
    render :passbook
  end

  def new
    @loan = ShgLoan.new(distribution_date: Date.current, loan_status: LoanStatus.default_active, loan_term_type: "Monthly")
    apply_loan_prefill(@loan)
  end

  def create
    @loan = ShgLoan.new(loan_params)
    @loan.created_by = current_user
    @loan.loan_status ||= LoanStatus.default_active

    unless loan_selection_available?(@loan)
      @loan.errors.add(:shg, "and member are not available for your login")
      return render :new, status: :unprocessable_entity
    end

    if product_required_for_current_user?(@loan)
      return render :new, status: :unprocessable_entity
    end

    if @loan.save
      store_loan_prefill
      if add_another_loan?
        redirect_to new_shg_loan_path(loan_prefill_redirect_params), notice: "SHG loan saved successfully. Add another loan."
      else
        redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), notice: "SHG loan saved successfully."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @loan.assign_attributes(loan_params)
    @loan.loan_status ||= LoanStatus.default_active
    unless loan_selection_available?(@loan)
      @loan.errors.add(:shg, "and member are not available for your login")
      return render :edit, status: :unprocessable_entity
    end

    if product_required_for_current_user?(@loan)
      return render :edit, status: :unprocessable_entity
    end

    if @loan.save
      redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), notice: "SHG loan updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    disable
  end

  def bulk_destroy
    bulk_disable
  end

  def disable
    if active_change_locked?(@loan)
      return redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), alert: "Assistant Admin approved SHG loan cannot be disabled."
    end

    @loan.update_columns(active: false, updated_at: Time.current)
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), notice: "SHG loan disabled successfully."
  end

  def update_product
    product_id = params.dig(:shg_loan, :product_id).presence
    return redirect_to(loan_index_row_path(@loan), alert: "Please select Product Code.") if product_id.blank?

    product = Product.find_by(id: product_id)
    return redirect_to(loan_index_row_path(@loan), alert: "Selected Product Code is not available.") unless product

    @loan.update_columns(product_id: product.id, updated_at: Time.current)
    redirect_to loan_index_row_path(@loan), notice: "Product Code updated successfully."
  end

  def bulk_disable
    result = disable_records(filtered_loans, params[:ids])
    redirect_to results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), notice: "SHG loans disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  private

  def require_loan_import_permission!
    redirect_back fallback_location: shg_loans_path, alert: "You do not have permission to import loan data." unless can_import_loan_data?
  end

  def require_shg_loan_manage_permission!
    return if can_manage_shg_loan?(@loan)

    redirect_back fallback_location: results_redirect_path(:shg_loans_path, LOAN_INDEX_PARAMS), alert: "This loan is not editable for your login."
  end

  def product_code_options
    Product.order(:name).map do |product|
      [ product_code_label(product), product.id ]
    end
  end

  def loan_index_scope
    filtered_loans(preload_emis: false).order(created_at: :desc, id: :desc)
  end

  def loan_index_row_path(loan)
    index_params = preserved_index_params(LOAN_INDEX_PARAMS)
    index_params[:page] = loan_index_page_for(loan)
    index_params.delete(:page) if index_params[:page].to_i <= 1

    "#{shg_loans_path(index_params)}#loan-#{loan.id}"
  end

  def loan_index_page_for(loan)
    current_page = params[:page].to_i
    return current_page if current_page.positive?

    preceding_count = filtered_loans(preload_emis: false)
      .where(
        "shg_loans.created_at > :created_at OR (shg_loans.created_at = :created_at AND shg_loans.id > :id)",
        created_at: loan.created_at,
        id: loan.id
      )
      .unscope(:order)
      .distinct
      .count("shg_loans.id")

    (preceding_count / DEFAULT_PAGE_SIZE) + 1
  end

  def set_loan_form_prefill
    @loan_form_prefill = loan_form_prefill_params
  end

  def loan_form_prefill_params
    saved_prefill = session[LOAN_PREFILL_SESSION_KEY].is_a?(Hash) ? session[LOAN_PREFILL_SESSION_KEY].slice(*LOAN_PREFILL_PARAMS.map(&:to_s)) : {}
    index_prefill = {
      "shg_id" => filter_param_value(:shg_id),
      "block_id" => filter_param_value(:block_id),
      "village_id" => filter_param_value(:village_id)
    }.compact_blank

    merge_loan_prefill(saved_prefill, index_prefill, submitted_loan_prefill_params)
  end

  def merge_loan_prefill(saved_prefill, index_prefill, submitted_prefill)
    prefill = saved_prefill.dup
    prefill.except!("village_id", "shg_id") if index_prefill["block_id"].present? && index_prefill["block_id"] != prefill["block_id"]
    prefill.except!("shg_id") if index_prefill["village_id"].present? && index_prefill["village_id"] != prefill["village_id"]

    prefill.merge(index_prefill).merge(submitted_prefill)
  end

  def submitted_loan_prefill_params
    return {} unless params[:shg_loan].respond_to?(:permit)

    params.require(:shg_loan).permit(*LOAN_PREFILL_PARAMS).to_h.compact_blank
  end

  def apply_loan_prefill(loan)
    attributes = @loan_form_prefill.slice(
      "shg_id", "product_id", "geography_type", "distribution_date",
      "loan_term_type", "loan_term", "principal_amount", "interest_percent"
    )
    if attributes["shg_id"].present?
      shg = visible_shgs.find_by(id: attributes["shg_id"])
      attributes.delete("shg_id") if shg.blank? ||
        (@loan_form_prefill["block_id"].present? && shg.block_id.to_s != @loan_form_prefill["block_id"].to_s) ||
        (@loan_form_prefill["village_id"].present? && shg.village_id.to_s != @loan_form_prefill["village_id"].to_s)
    end

    loan.assign_attributes(attributes)
  end

  def store_loan_prefill
    prefill = submitted_loan_prefill_params
    prefill.present? ? session[LOAN_PREFILL_SESSION_KEY] = prefill : session.delete(LOAN_PREFILL_SESSION_KEY)
  end

  def add_another_loan?
    params[:add_another].present?
  end

  def loan_prefill_redirect_params
    preserved_index_params(LOAN_INDEX_PARAMS).merge(shg_loan: session[LOAN_PREFILL_SESSION_KEY])
  end

  def start_async_loan_import(file)
    filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : File.basename(file.path)
    import = LoanImport.create!(
      user: current_user,
      filename: filename,
      status: "queued"
    )

    import_dir = Rails.root.join("tmp", "loan_imports")
    FileUtils.mkdir_p(import_dir)
    import_path = import_dir.join("#{import.id}-#{SecureRandom.hex(8)}#{File.extname(filename)}")
    FileUtils.cp(file.path, import_path)

    LoanImportJob.perform_later(import.id, import_path.to_s, filename, current_user.id)
    import
  end

  def loan_selection_available?(loan)
    shg = visible_shgs.find_by(id: loan.shg_id)
    return false unless shg
    return false unless visible_shg_members.where(shg_id: loan.shg_id).exists?(id: loan.shg_member_id)

    selection = params[:shg_loan] || {}
    block_id = selection[:block_id].presence || selection["block_id"].presence
    village_id = selection[:village_id].presence || selection["village_id"].presence

    return false if block_id.present? && shg.block_id.to_s != block_id.to_s
    return false if village_id.present? && shg.village_id.to_s != village_id.to_s

    true
  end

  def set_filter_options
    if can_filter_loan_state_district_crp?
      @states = filter_states
      @districts = limited_filter_records(filter_districts_for_params, filter_param_values(:district_id))
      @crps = limited_user_filter_records(filter_crps, filter_param_values(:crp_id))
    end

    @blocks = limited_filter_records(filter_blocks_for_params, filter_param_values(:block_id))
    @villages = limited_filter_records(filter_villages_for_params, filter_param_values(:village_id))
    @shgs = limited_filter_records(loan_filter_shgs, filter_param_values(:shg_id))
  end

  def filtered_loans(preload_emis: true)
    loans = visible_shg_loans
      .includes(:activity, :created_by, :loan_status, :product, :shg_member, shg: [ :state, :district, :block, :village ])
    loans = loans.includes(:shg_loan_emis) if preload_emis

    loans = loans.where(distribution_date: params[:date_from]..) if params[:date_from].present?
    loans = loans.where(distribution_date: ..params[:date_to]) if params[:date_to].present?
    if can_filter_loan_state_district_crp?
      state_ids = filter_param_ids(:state_id)
      district_ids = filter_param_ids(:district_id)
      crp_ids = filter_param_ids(:crp_id)
      loans = loans.joins(:shg).where(shgs: { state_id: state_ids }) if state_ids.present?
      loans = loans.joins(:shg).where(shgs: { district_id: district_ids }) if district_ids.present?
      loans = loans.where(created_by_id: crp_ids) if crp_ids.present?
    end
    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    shg_ids = filter_param_ids(:shg_id)
    loans = loans.joins(:shg).where(shgs: { block_id: block_ids }) if block_ids.present?
    loans = loans.joins(:shg).where(shgs: { village_id: village_ids }) if village_ids.present?
    loans = loans.where(shg_id: shg_ids) if shg_ids.present?
    loans = active_record_filter(loans)
    loans = search_loans(loans)
    loans
  end

  def filtered_stale_loan_no_members
    members = visible_shg_members
      .left_outer_joins(:shg_loans)
      .where.not(loan_no: [ nil, "" ])
      .where(shg_loans: { id: nil })

    if can_filter_loan_state_district_crp?
      state_ids = filter_param_ids(:state_id)
      district_ids = filter_param_ids(:district_id)
      crp_ids = filter_param_ids(:crp_id)
      members = members.joins(:shg).where(shgs: { state_id: state_ids }) if state_ids.present?
      members = members.joins(:shg).where(shgs: { district_id: district_ids }) if district_ids.present?
      members = members.joins(:shg).where(shgs: { created_by_id: crp_ids }) if crp_ids.present?
    end

    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    shg_ids = filter_param_ids(:shg_id)
    members = members.joins(:shg).where(shgs: { block_id: block_ids }) if block_ids.present?
    members = members.joins(:shg).where(shgs: { village_id: village_ids }) if village_ids.present?
    members = members.where(shg_id: shg_ids) if shg_ids.present?
    members = active_record_filter(members)
    search_stale_loan_no_members(members)
  end

  def search_stale_loan_no_members(members)
    query = params[:q].to_s.strip
    return members if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    members.where(
      [
        "CAST(shg_members.id AS TEXT) ILIKE :query",
        "LOWER(shg_members.loan_no) LIKE :query"
      ].join(" OR "),
      query: pattern
    ).distinct
  end

  def can_filter_loan_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
  end

  def loan_filter_option_scope
    visible_shg_loans.joins(:shg)
  end

  def loan_filter_crps
    crp_ids = filter_crps.map(&:id) & loan_filter_option_scope.distinct.pluck(:created_by_id)
    limited_filter_records(User.where(id: crp_ids).includes(:user_type).order(:name), params[:crp_id])
  end

  def loan_filter_shgs
    shgs = visible_shgs
    state_ids = filter_param_ids(:state_id)
    district_ids = filter_param_ids(:district_id)
    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    shgs = shgs.where(state_id: state_ids) if state_ids.present?
    shgs = shgs.where(district_id: district_ids) if district_ids.present?
    shgs = shgs.where(block_id: block_ids) if block_ids.present?
    shgs = shgs.where(village_id: village_ids) if village_ids.present?
    shgs.order(:name)
  end

  def search_loans(loans)
    query = params[:q].to_s.strip
    return loans if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    loans.left_joins(:shg_member, :product, :loan_status, :created_by, shg: [ :state, :district, :block, :village ])
      .where(
        [
          "CAST(shg_loans.id AS TEXT) ILIKE :query",
          "CAST(shg_loans.principal_amount AS TEXT) ILIKE :query",
          "CAST(shg_loans.total_payable AS TEXT) ILIKE :query",
          "LOWER(shg_loans.source_crp_identifier) LIKE :query",
          "LOWER(shg_loans.source_crp_name) LIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(shg_members.loan_no) LIKE :query",
          "LOWER(shg_members.mobile) LIKE :query",
          "LOWER(products.name) LIKE :query",
          "LOWER(products.code) LIKE :query",
          "LOWER(loan_statuses.name) LIKE :query",
          "LOWER(states.name) LIKE :query",
          "LOWER(districts.name) LIKE :query",
          "LOWER(blocks.name) LIKE :query",
          "LOWER(villages.name) LIKE :query",
          "LOWER(users.name) LIKE :query",
          "LOWER(users.login_id) LIKE :query"
        ].join(" OR "),
        query: pattern
      ).distinct
  end

  def stream_loan_no_check_csv(loans, stale_members)
    stream_csv("loan-no-check-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "Issue", "Loan Sequence", "Loan No", "Loan ID", "Loan Record",
        "Member ID", "Member Record", "SHG ID"
      ])

      each_ordered_batch(loans) do |batch|
        batch.each do |loan|
          stream << CSV.generate_line(loan_no_check_loan_row(loan))
        end
      end

      each_ordered_batch(stale_members) do |batch|
        batch.each do |member|
          stream << CSV.generate_line(loan_no_check_stale_member_row(member))
        end
      end
    end
  end

  def loan_no_check_loan_row(loan)
    member = loan.shg_member

    [
      "OK - loan record exists",
      loan_no_sequence(member.loan_no),
      member.loan_no,
      loan.id,
      loan.active? ? "Active" : "Inactive",
      member.id,
      member.active? ? "Active" : "Inactive",
      loan.shg_id
    ]
  end

  def loan_no_check_stale_member_row(member)
    [
      "NO LOAN RECORD - stale member loan no",
      loan_no_sequence(member.loan_no),
      member.loan_no,
      nil,
      nil,
      member.id,
      member.active? ? "Active" : "Inactive",
      member.shg_id
    ]
  end

  def loan_no_sequence(loan_no)
    loan_no.to_s[/-(\d+)\z/, 1]&.to_i
  end

  def loan_number_ordered_loans(loans)
    loans.left_joins(:shg_member).distinct(false).reorder(Arel.sql(loan_number_order_sql), Arel.sql("shg_loans.id ASC"))
  end

  def loan_number_ordered_members(members)
    members.distinct(false).reorder(Arel.sql(loan_number_order_sql), Arel.sql("shg_members.id ASC"))
  end

  def loan_number_order_sql
    "COALESCE(NULLIF(substring(shg_members.loan_no FROM '-([0-9]+)$'), '')::integer, 2147483647) ASC, shg_members.loan_no ASC"
  end

  def each_ordered_batch(relation, batch_size: 1_000)
    offset = 0

    loop do
      batch = relation.limit(batch_size).offset(offset).to_a
      break if batch.empty?

      yield batch
      offset += batch_size
    end
  end

  def stream_loans_csv(loans)
    stream_csv("shg-loans-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "SHG Name", "Member", "Spouse/Father Name", "Loan No", "Aadhaar Number",
        "Work/Activity", "Date of Birth", "Office Location", "Borrower Short Address",
        "State", "District", "Block", "Village", "CRP ID",
        "CRPName", "Product Code", "Disbursement Date", "Loan Status",
        "Term Type", "Loan term", "Principal", "Annual Interest Percent",
        "Interest Amount", "Total Payable", "Principal Collected",
        "Interest collected", "Paid", "Remaining", "Mobile",
        "Monthly hh income"
      ])

      each_ordered_batch(loans) do |batch|
        emi_totals = emi_totals_by_loan_id(batch.map(&:id))

        batch.each do |loan|
          totals = emi_totals.fetch(loan.id, default_emi_totals)
          paid_amount = source_import_loan?(loan) ? loan_paid_amount(loan) : totals[:paid_amount]
          total_payable = loan_total_payable(loan)

          stream << CSV.generate_line([
            loan.shg.name,
            loan.shg_member.name,
            loan.shg_member.spouse_father_name,
            loan.shg_member.loan_no,
            loan.shg_member.aadhaar_no,
            loan.work_activity_name,
            loan.shg_member.dob,
            loan.shg.office_location,
            loan.shg.borrower_short_address,
            loan.shg.state.name,
            loan.shg.district.name,
            loan.shg.block.name,
            loan.shg.village.name,
            loan_crp_identifier(loan),
            loan_crp_name(loan),
            product_code_label(loan.product),
            formatted_import_date(loan.distribution_date),
            loan_status_label(loan),
            loan.loan_term_type,
            loan.loan_term,
            loan.principal_amount,
            loan.interest_percent,
            loan_interest_amount(loan),
            total_payable,
            source_import_loan?(loan) ? loan_principal_collect(loan) : totals[:principal_collected],
            source_import_loan?(loan) ? loan_interest_collect(loan) : totals[:interest_collected],
            paid_amount,
            source_import_loan?(loan) ? loan_remaining_amount(loan) : total_payable.to_d - paid_amount.to_d,
            loan.shg_member.mobile,
            loan.shg_member.monthly_income
          ])
        end
      end
    end
  end

  def emi_totals_by_loan_id(loan_ids)
    ShgLoanEmi.where(shg_loan_id: loan_ids)
      .group(:shg_loan_id)
      .pluck(
        :shg_loan_id,
        Arel.sql("COALESCE(SUM(paid_amount), 0)"),
        Arel.sql("COALESCE(SUM(LEAST(paid_amount, interest_amount)), 0)"),
        Arel.sql("COALESCE(SUM(LEAST(GREATEST(paid_amount - LEAST(paid_amount, interest_amount), 0), principal_amount)), 0)")
      )
      .each_with_object({}) do |(loan_id, paid, interest, principal), totals|
        totals[loan_id] = {
          paid_amount: paid.to_d,
          interest_collected: interest.to_d,
          principal_collected: principal.to_d
        }
      end
  end

  def default_emi_totals
    { paid_amount: 0.to_d, interest_collected: 0.to_d, principal_collected: 0.to_d }
  end

  def loan_crp_identifier(loan)
    loan.source_crp_identifier.presence || loan.created_by&.login_id
  end

  def loan_crp_name(loan)
    loan.source_crp_name.presence || loan.created_by&.name
  end

  def loan_status_label(loan)
    label = if source_import_loan?(loan)
      loan.source_loan_status.presence || loan.loan_status.name
    else
      loan.loan_status.name
    end

    label.to_s.casecmp?("overdue") ? "Paid" : label
  end

  def loan_interest_amount(loan)
    loan.source_interest_amount.presence || loan.interest_amount
  end

  def loan_total_payable(loan)
    loan.source_total_payable.presence || loan.total_payable
  end

  def loan_principal_collect(loan)
    loan.source_principal_collect.presence || loan_emi_totals_for(loan)[:principal_collected] || loan.cumulative_principal_collected
  end

  def loan_interest_collect(loan)
    loan.source_interest_collect.presence || loan_emi_totals_for(loan)[:interest_collected] || loan.cumulative_interest_collected
  end

  def loan_paid_amount(loan)
    loan.source_paid.presence || loan_emi_totals_for(loan)[:paid_amount] || loan.total_paid
  end

  def loan_remaining_amount(loan)
    loan.source_remaining.presence || loan_total_payable(loan).to_d - loan_paid_amount(loan).to_d
  end

  def loan_emi_totals_for(loan)
    @loan_emi_totals&.fetch(loan.id, default_emi_totals) || {}
  end

  def formatted_import_date(date)
    date&.strftime("%d/%m/%Y")
  end

  def source_import_loan?(loan)
    loan.source_crp_identifier.present? ||
      loan.source_crp_name.present? ||
      loan.source_loan_status.present? ||
      loan.source_total_payable.present? ||
      loan.source_paid.present?
  end

  def product_code_label(product)
    return "-" unless product

    product.name.presence || "-"
  end

  def product_required_for_current_user?(loan)
    return false if current_user&.crp?
    return false if loan.product_id.present?

    loan.errors.add(:product, "must be selected by DC/Admin")
    true
  end

  helper_method :loan_crp_identifier, :loan_crp_name, :loan_status_label,
    :loan_interest_amount, :loan_total_payable, :loan_principal_collect,
    :loan_interest_collect, :loan_paid_amount, :loan_remaining_amount,
    :formatted_import_date, :product_code_label

  def import_loans(file, progress_import: nil)
    result = { rows: 0, loans: 0, approved_shgs: 0, skipped: 0, errors: [] }
    initialize_import_context

    quiet_import_logging do
      import_rows(file).each_with_index.each_slice(IMPORT_BATCH_SIZE) do |indexed_rows|
        loan_batch = []
        emi_batch = []

        ActiveRecord::Base.transaction do
          processed_rows = normalize_import_batch(indexed_rows, result)
          cache_existing_import_shgs!(processed_rows)
          result[:approved_shgs] += insert_missing_import_shgs!(processed_rows)
          approve_existing_import_shgs!(processed_rows, result)
          create_import_members_for_rows!(processed_rows)

          processed_rows.each do |processed|
            attrs = processed.fetch(:attrs)
            shg = cached_import_shg(attrs, processed.fetch(:village))
            member = processed.fetch(:member)
            loan_attributes = imported_loan_attributes(attrs, shg, member, processed.fetch(:created_by))
            loan_batch << loan_attributes
            emi_batch << imported_summary_emi_attributes(attrs, loan_attributes)
            result[:loans] += 1
          end

          insert_imported_loan_batch!(loan_batch, emi_batch)
          result[:approved_shgs] += submit_ready_import_shgs!(processed_rows)
        end
        update_import_progress(progress_import, result)
      end
    end

    result
  end

  def update_import_progress(import, result)
    return unless import

    import.update_columns(
      total_rows: result[:rows],
      total_loans: result[:loans],
      approved_shgs: result[:approved_shgs],
      skipped_rows: result[:skipped],
      error_message: result[:errors].join(" | ").presence,
      updated_at: Time.current
    )
  end

  def quiet_import_logging(&block)
    logger = ActiveRecord::Base.logger
    return yield unless logger&.respond_to?(:silence)

    logger.silence(Logger::WARN, &block)
  end

  def normalize_import_batch(indexed_rows, result)
    indexed_rows.filter_map do |row, index|
      next if import_blank_row?(row)

      begin
        attrs = normalized_import_row(row)
        next if import_header_row?(attrs)

        result[:rows] += 1
        state = cached_import_state(attrs.fetch(:state))
        district = cached_import_district(state, attrs.fetch(:district))
        block = cached_import_block(district, attrs.fetch(:block))
        village = cached_import_village(block, attrs.fetch(:village))
        created_by = import_crp(attrs) || @import_current_user
        { attrs: attrs, state: state, district: district, block: block, village: village, created_by: created_by }
      rescue ActiveRecord::RangeError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError => e
        result[:skipped] += 1
        result[:errors] << "Row #{index + 2}: #{import_error_message(e)}" if result[:errors].size < 5
        nil
      end
    end
  end

  def import_blank_row?(row)
    fields = row.fields.map { |field| field.to_s.strip }
    return true if fields.all?(&:blank?)
    return true if placeholder_import_loan_row?(fields)

    [ 0, 1, 2, 3, 4, 5 ].all? { |index| fields[index].blank? }
  end

  def placeholder_import_loan_row?(fields)
    PLACEHOLDER_IMPORT_LOAN_VALUES.include?(fields.first.to_s.downcase) && fields.drop(1).all?(&:blank?)
  end

  def initialize_import_context
    @import_current_user = current_user
    @import_states = {}
    @import_districts = {}
    @import_blocks = {}
    @import_villages = {}
    @import_shgs = {}
    @import_products = {}
    @import_activities = {}
    @import_occupations = {}
    @import_crps = {}
    @import_crp_users_by_name = users_with_role_codes("CRP").index_by { |user| user.name.to_s.downcase }
    @import_loan_statuses = {}
    @next_import_shg_code_no = Shg.maximum(:id).to_i + 1
  end

  def cached_import_state(name)
    @import_states[name] ||= State.find_or_create_by!(name: name)
  end

  def cached_import_district(state, name)
    @import_districts[[ state.id, name ]] ||= District.find_or_create_by!(state: state, name: name)
  end

  def cached_import_block(district, name)
    @import_blocks[[ district.id, name ]] ||= Block.find_or_create_by!(district: district, name: name)
  end

  def cached_import_village(block, name)
    @import_villages[[ block.id, name ]] ||= Village.find_or_create_by!(block: block, name: name)
  end

  def cached_import_product(name)
    canonical_name = name.to_s.squish
    normalized_name = canonical_name.downcase
    @import_products[normalized_name] ||= Product.where("LOWER(name) = :value OR LOWER(code) = :value", value: normalized_name).first || Product.create!(name: canonical_name)
  end

  def cached_import_activity(name)
    @import_activities[name] ||= Activity.find_or_create_by!(name: name)
  end

  def default_import_activity
    @default_import_activity ||= Activity.find_or_create_by!(name: default_import_activity_name)
  end

  def default_import_activity_name
    "General"
  end

  def cached_import_occupation(name)
    @import_occupations[name] ||= Occupation.find_or_create_by!(name: name)
  end

  def import_file_content(file)
    content = File.binread(file.path).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    content.delete_prefix("\uFEFF")
  end

  def import_rows(file)
    if excel_import_file?(file)
      xlsx_import_rows(file)
    else
      Enumerator.new do |yielder|
        CSV.foreach(file.path, headers: true, encoding: "bom|utf-8:utf-8") do |row|
          yielder << SpreadsheetImportRow.new(row.headers, row.fields)
        end
      end
    end
  end

  def excel_import_file?(file)
    filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : file.path.to_s
    File.extname(filename).casecmp?(".xlsx")
  end

  def normalized_import_row(row)
    {
      state: required_import_value(row, "state", "state - mp/jh", indexes: [ 2 ]),
      district: required_import_value(row, "district"),
      block: required_import_value(row, "block"),
      village: required_import_value(row, "village"),
      shg: required_import_value(row, "shg", "shg name", "group"),
      member: required_import_value(row, "member", "member name"),
      product: import_value(row, "product", "product type", "product code", indexes: [ 8 ]).presence || "Imported Loan",
      activity: default_import_activity_name,
      occupation: import_value(row, "occupation").presence || "Imported",
      member_activity: import_value(row, "work/activity", "work activity", "member activity", "activity", "loan activity").presence || default_import_activity_name,
      spouse_father_name: import_value(row, "spouse/father name", "spouse father name", "father name", "spouse name"),
      aadhaar_no: import_digits(row, "aadhaar", "aadhaar no", "aadhaar number", "aadhar", "aadhar no", "aadhar number"),
      gender: import_value(row, "gender"),
      dob: import_date(row, "dob", "date of birth"),
      mobile: import_digits(row, "mobile", "mobile no", "mobile_no", "phone", "phone number", "phone no", "phone_no", "contact", "contact no", "borrower phone number", indexes: [ 21 ]),
      monthly_income: import_value(row, "monthly hh income", "monthly income", "monthly_income", "income", "member income", indexes: [ 22, 23, 24 ]),
      borrower_short_address: import_value(row, "borrower short address", "short address", "address"),
      office_location: import_value(row, "office location", "office"),
      distribution_date: import_date(row, "disbursement date", "distribution date", "distribution_date", indexes: [ 9 ]) || Date.current,
      geography_type: import_choice(row, ShgLoan::GEOGRAPHY_TYPES, "geography", "geography type", "type of geography") || "Rural",
      loan_status: import_value(row, "loan status", "loan_status", indexes: [ 10 ]),
      loan_term_type: import_choice(row, ShgLoan::TERM_TYPES, "term type", "loan term type", "loan_term_type") || "Monthly",
      loan_term: import_value(row, "loan term", "loan_term", "term", indexes: [ 12 ]).presence || 1,
      principal_amount: required_import_value(row, "principal", "principal amount", "principal_amount", indexes: [ 13 ]),
      interest_percent: import_interest_percent(row),
      interest_amount: import_value(row, "interest amount", "interest_amount", indexes: [ 15 ]),
      total_payable: import_value(row, "total payable", "total_payable", "principal + interest amount", indexes: [ 16 ]),
      principal_collect: import_value(row, "principal collected", "principal collect", "pricipal collect", indexes: [ 17 ]),
      interest_collect: import_value(row, "interest collected", "interest collect", "intrest collect", indexes: [ 18 ]),
      paid_amount: import_paid_amount(row),
      remaining_amount: import_value(row, "remaining", "remaining amount", indexes: [ 20 ]),
      crp_email: import_value(row, "crp email", "crp_email"),
      crp_identifier: import_value(row, "crp id", "crp_id", "crp no", "crp", "no. id", indexes: [ 6, 7 ]),
      crp_name: import_value(row, "crpname", "crp name", "crp_name").presence || row.fields[7].to_s.strip
    }
  end

  def import_header_row?(attrs)
    attrs[:shg].to_s.casecmp?("shg") ||
      attrs[:member].to_s.casecmp?("member") ||
      attrs[:state].to_s.downcase.include?("state -")
  end

  def required_import_value(row, *keys, indexes: [])
    value = import_value(row, *keys, indexes: indexes)
    return value if value.present?

    raise ActiveRecord::RecordInvalid.new(ShgLoan.new.tap { |loan| loan.errors.add(:base, "CSV column #{keys.first} is required") })
  end

  def import_error_message(error)
    if error.respond_to?(:record) && error.record&.errors&.any?
      error.record.errors.full_messages.to_sentence
    else
      error.message
    end
  end

  def import_value(row, *keys, indexes: [])
    value = keys.lazy.map { |key| import_value_for_key(row, key) }.find(&:present?)
    value ||= indexes.lazy.map { |index| row.fields[index] }.find(&:present?)
    value.to_s.strip
  end

  def import_digits(row, *keys, indexes: [])
    import_value(row, *keys, indexes: indexes).gsub(/\D/, "")
  end

  def normalized_import_identifier(value)
    raw = value.to_s.strip
    return "" if raw.blank?

    if raw.match?(/\A\d+(\.0+)?\z/)
      raw.to_d.to_i.to_s
    elsif raw.match?(/\A\d+(\.\d+)?e\+?\d+\z/i)
      raw.to_d.to_i.to_s
    else
      raw.gsub(/\D/, "")
    end
  end

  def import_date(row, *keys, indexes: [])
    value = import_value(row, *keys, indexes: indexes)
    return if value.blank?
    return Date.new(1899, 12, 30) + value.to_i if value.match?(/\A\d+(\.0+)?\z/)
    return parsed_indian_date(value) if value.match?(/\A\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}\z/)

    Date.parse(value)
  rescue Date::Error
    nil
  end

  def parsed_indian_date(value)
    normalized = value.tr(".-", "/")
    format = normalized.split("/").last.length == 2 ? "%d/%m/%y" : "%d/%m/%Y"
    Date.strptime(normalized, format)
  end

  def import_choice(row, choices, *keys)
    value = import_value(row, *keys)
    choices.find { |choice| choice.casecmp?(value) }
  end

  def import_paid_amount(row)
    paid = import_value(row, "paid", "paid amount", "paid_amount", indexes: [ 19 ])
    return paid if paid.present?

    principal_collected = import_value(row, "principal collected", "principal collect", "pricipal collect", indexes: [ 17 ]).to_d
    interest_collected = import_value(row, "interest collected", "interest collect", "intrest collect", indexes: [ 18 ]).to_d
    collected = principal_collected + interest_collected
    collected.positive? ? collected.to_s : nil
  end

  def import_interest_percent(row)
    value = import_decimal_string(row, "annual interest percent", "annual_interest_percent", "interest percent", "interest_percent", "interest per month", "interest_per_month", indexes: [ 14 ])
    return if value.blank?

    percent = value.to_d
    return if percent.negative? || percent >= 1000

    value
  end

  def import_decimal_string(row, *keys, indexes: [])
    value = import_value(row, *keys, indexes: indexes)
    return if value.blank?

    cleaned = value.to_s.strip.delete(",").delete("%")
    cleaned = cleaned.gsub(/[^\d.\-]/, "")
    cleaned.presence
  end

  def import_value_for_key(row, key)
    normalized_key = normalized_import_key(key)
    return row.normalized_value(normalized_key) if row.respond_to?(:normalized_value)

    candidates = [ key, key.to_s.titleize, key.to_s.upcase, key.to_s.humanize ]
    direct_value = candidates.lazy.map { |candidate| row[candidate] }.find(&:present?)
    return direct_value if direct_value.present?

    header = import_headers(row).find { |candidate| normalized_import_key(candidate) == normalized_key }
    header.present? ? row[header] : nil
  end

  def import_headers(row)
    row.respond_to?(:headers) ? row.headers.compact : []
  end

  def normalized_import_key(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end

  def xlsx_import_rows(file)
    Enumerator.new do |yielder|
      Zip::File.open(file.path) do |xlsx|
        shared_strings = xlsx_shared_strings(xlsx)
        style_formats = xlsx_style_formats(xlsx)
        sheet_entry = xlsx.glob("xl/worksheets/sheet*.xml").min_by(&:name)
        next unless sheet_entry

        headers = nil
        xlsx_sheet_rows(sheet_entry, shared_strings, style_formats).each do |fields|
          next if fields.blank? || fields.none?(&:present?)

          if headers.nil?
            headers = fields
            next
          end

          yielder << SpreadsheetImportRow.new(headers, fields)
        end
      end
    end
  end

  def xlsx_sheet_rows(sheet_entry, shared_strings, style_formats)
    Enumerator.new do |yielder|
      fields = nil
      cell_column = nil
      cell_type = nil
      cell_style = nil
      value = +""
      inline_text = +""
      in_value = false
      in_text = false

      Nokogiri::XML::Reader(sheet_entry.get_input_stream).each do |node|
        if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          case node.name
          when "row"
            fields = []
          when "c"
            cell_column = xlsx_column_index(node.attribute("r"))
            cell_type = node.attribute("t")
            cell_style = node.attribute("s")
            value = +""
            inline_text = +""
          when "v"
            in_value = true
          when "t"
            in_text = true
          end
        elsif node.node_type == Nokogiri::XML::Reader::TYPE_TEXT || node.node_type == Nokogiri::XML::Reader::TYPE_CDATA
          value << node.value.to_s if in_value
          inline_text << node.value.to_s if in_text
        elsif node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT
          case node.name
          when "v"
            in_value = false
          when "t"
            in_text = false
          when "c"
            fields[cell_column] = xlsx_cell_text(cell_type, cell_style, value, inline_text, shared_strings, style_formats) if fields && cell_column
            cell_column = nil
            cell_type = nil
            cell_style = nil
          when "row"
            yielder << fields.map { |field| field.to_s.strip } if fields
            fields = nil
          end
        end
      end
    end
  end

  def xlsx_shared_strings(xlsx)
    entry = xlsx.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    strings = []
    current = nil
    in_text = false

    Nokogiri::XML::Reader(entry.get_input_stream).each do |node|
      if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
        case node.name
        when "si"
          current = +""
        when "t"
          in_text = true
        end
      elsif node.node_type == Nokogiri::XML::Reader::TYPE_TEXT || node.node_type == Nokogiri::XML::Reader::TYPE_CDATA
        current << node.value.to_s if in_text && current
      elsif node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT
        case node.name
        when "t"
          in_text = false
        when "si"
          strings << current.to_s
          current = nil
        end
      end
    end

    strings
  end

  def xlsx_style_formats(xlsx)
    entry = xlsx.find_entry("xl/styles.xml")
    return [] unless entry

    document = Nokogiri::XML(entry.get_input_stream.read)
    document.remove_namespaces!
    custom_formats = document.xpath("//numFmt").to_h { |node| [ node["numFmtId"], node["formatCode"] ] }
    built_in_formats = {
      "14" => "m/d/yy",
      "15" => "d-mmm-yy",
      "16" => "d-mmm",
      "17" => "mmm-yy",
      "22" => "m/d/yy h:mm"
    }
    formats = built_in_formats.merge(custom_formats)

    document.xpath("//cellXfs/xf").map { |node| formats[node["numFmtId"]] }
  end

  def xlsx_cell_text(cell_type, cell_style, value, inline_text, shared_strings, style_formats)
    return inline_text if inline_text.present?
    return shared_strings[value.to_i].to_s if cell_type == "s"
    return xlsx_formatted_date(value, style_formats[cell_style.to_i]) if xlsx_date_style?(value, style_formats[cell_style.to_i])

    value.to_s
  end

  def xlsx_date_style?(value, format)
    value.present? && format.to_s.match?(/[dmy]/i) && value.match?(/\A\d+(\.\d+)?\z/)
  end

  def xlsx_formatted_date(value, format)
    date = Date.new(1899, 12, 30) + value.to_i
    normalized = format.to_s.downcase

    if normalized.include?("m/d")
      date.strftime("%m/%d/%Y")
    elsif normalized.include?("d/m")
      date.strftime("%d/%m/%Y")
    elsif normalized.include?("d-m")
      date.strftime("%d-%m-%Y")
    else
      date.strftime("%d/%m/%Y")
    end
  end

  def xlsx_column_index(cell_reference)
    letters = cell_reference.to_s[/\A[A-Z]+/]
    return 0 if letters.blank?

    letters.chars.reduce(0) { |sum, char| (sum * 26) + (char.ord - "A".ord + 1) } - 1
  end

  class SpreadsheetImportRow
    attr_reader :headers, :fields

    def initialize(headers, fields)
      @headers = headers
      @fields = fields
      @values = {}
      @normalized_values = {}
      headers.each_with_index do |header, index|
        next if header.blank?

        @values[header] ||= fields[index]
        @normalized_values[normalized_header_key(header)] ||= fields[index]
      end
    end

    def [](key)
      @values[key]
    end

    def normalized_value(key)
      @normalized_values[key]
    end

    private

    def normalized_header_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
    end
  end

  def find_or_create_imported_shg(attrs, state, district, block, village, created_by = nil)
    @import_shgs[[ village.id, attrs[:shg] ]] ||= Shg.find_or_initialize_by(name: attrs[:shg], village: village).tap do |shg|
      next if shg.persisted?

      shg.state = state
      shg.district = district
      shg.block = block
      shg.linkage_date = attrs[:distribution_date]
      shg.created_by = created_by || import_crp(attrs) || @import_current_user
      shg.shg_code = next_import_shg_code(village)
      shg.office_location = attrs[:office_location].presence
      shg.borrower_short_address = attrs[:borrower_short_address].presence
      shg.save!
    end
  end

  def next_import_shg_code(village)
    code = "IMP-#{village.id}-#{@next_import_shg_code_no}"
    @next_import_shg_code_no += 1
    code
  end

  def cache_existing_import_shgs!(processed_rows)
    village_ids = processed_rows.map { |processed| processed[:village].id }.uniq
    names = processed_rows.map { |processed| processed.dig(:attrs, :shg) }.compact_blank.uniq
    return if village_ids.blank? || names.blank?

    Shg.where(village_id: village_ids, name: names).find_each do |shg|
      cache_import_shg(shg)
    end
  end

  def insert_missing_import_shgs!(processed_rows)
    missing_shgs = {}

    processed_rows.each do |processed|
      attrs = processed.fetch(:attrs)
      village = processed.fetch(:village)
      key = [ village.id, attrs[:shg] ]
      next if @import_shgs.key?(key)

      missing_shgs[key] ||= processed
    end

    return 0 if missing_shgs.blank?

    timestamp = Time.current
    auto_approve = current_user&.assistant_admin?
    rows = missing_shgs.values.map do |processed|
      {
        state_id: processed.fetch(:state).id,
        district_id: processed.fetch(:district).id,
        block_id: processed.fetch(:block).id,
        village_id: processed.fetch(:village).id,
        created_by_id: processed.fetch(:created_by)&.id,
        name: processed.dig(:attrs, :shg),
        shg_code: next_import_shg_code(processed.fetch(:village)),
        office_location: processed.dig(:attrs, :office_location).presence,
        borrower_short_address: processed.dig(:attrs, :borrower_short_address).presence,
        linkage_date: processed.dig(:attrs, :distribution_date),
        approval_status: auto_approve ? "approved" : "pending_dc",
        assistant_approved_by_id: auto_approve ? current_user.id : nil,
        assistant_approved_at: auto_approve ? timestamp : nil,
        approved_by_id: auto_approve ? current_user.id : nil,
        approved_at: auto_approve ? timestamp : nil,
        active: true,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    inserted = Shg.insert_all!(rows, returning: %w[id village_id name approval_status])
    inserted.rows.each do |row|
      data = inserted.columns.zip(row).to_h
      cache_import_shg(
        ImportShgReference.new(
          id: data.fetch("id"),
          village_id: data.fetch("village_id"),
          name: data.fetch("name"),
          approved: data.fetch("approval_status") == "approved"
        )
      )
    end

    auto_approve ? rows.size : 0
  end

  def approve_existing_import_shgs!(processed_rows, result)
    return unless current_user&.assistant_admin?

    processed_rows
      .filter_map { |processed| cached_import_shg(processed.fetch(:attrs), processed.fetch(:village)) }
      .uniq { |shg| shg.id }
      .each do |shg|
      result[:approved_shgs] += 1 if shg.is_a?(Shg) && approve_imported_shg!(shg)
    end
  end

  def submit_ready_import_shgs!(processed_rows)
    shg_ids = processed_rows
      .filter_map { |processed| cached_import_shg(processed.fetch(:attrs), processed.fetch(:village))&.id }
      .uniq
    return 0 if shg_ids.blank?

    submitted = 0
    Shg.where(id: shg_ids, approval_status: "draft").find_each do |shg|
      submitted += 1 if shg.submit_for_approval_if_ready!
    end
    submitted
  end

  def cached_import_shg(attrs, village)
    @import_shgs[[ village.id, attrs[:shg] ]]
  end

  def cache_import_shg(shg)
    @import_shgs[[ shg.village_id, shg.name ]] = shg
  end

  def approve_imported_shg!(shg)
    return false unless current_user&.assistant_admin?
    return false if shg.approved?

    shg.update!(
      approval_status: "approved",
      assistant_approved_by: current_user,
      assistant_approved_at: Time.current,
      approved_by: current_user,
      approved_at: Time.current
    )
  end

  def create_import_members_for_rows!(processed_rows)
    timestamp = Time.current
    aadhaar_values = processed_rows.map { |processed| processed.dig(:attrs, :aadhaar_no).presence }.compact_blank.uniq
    existing_aadhaar = aadhaar_values.present? ? ShgMember.where(aadhaar_no: aadhaar_values).pluck(:aadhaar_no).to_set : Set.new
    batch_aadhaar = Set.new

    rows = processed_rows.map do |processed|
      attrs = processed.fetch(:attrs)
      shg = cached_import_shg(attrs, processed.fetch(:village))
      aadhaar_no = attrs[:aadhaar_no].presence
      if aadhaar_no.present? && (existing_aadhaar.include?(aadhaar_no) || batch_aadhaar.include?(aadhaar_no))
        aadhaar_no = nil
      else
        batch_aadhaar.add(aadhaar_no) if aadhaar_no.present?
      end

      {
        shg_id: shg.id,
        occupation_id: cached_import_occupation(attrs[:occupation]).id,
        activity_id: cached_import_activity(attrs[:member_activity]).id,
        work_activity: attrs[:member_activity].presence,
        name: attrs[:member],
        spouse_father_name: attrs[:spouse_father_name],
        aadhaar_no: aadhaar_no,
        loan_no: nil,
        gender: attrs[:gender],
        dob: attrs[:dob],
        mobile: attrs[:mobile],
        monthly_income: attrs[:monthly_income].presence,
        active: true,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    return if rows.blank?

    inserted = ShgMember.insert_all!(rows, returning: %w[id shg_id name])
    inserted.rows.each_with_index do |row, index|
      data = inserted.columns.zip(row).to_h
      processed_rows[index][:member] = ImportMemberReference.new(
        id: data.fetch("id"),
        shg_id: data.fetch("shg_id"),
        name: data.fetch("name")
      )
    end
  end

  def create_imported_loan(attrs, shg, member)
    loan = ShgLoan.new(imported_loan_attributes(attrs, shg, member).except(:created_at, :updated_at))
    loan.manual_import_totals = true

    loan.save!
    create_imported_summary_emi!(loan) if loan.manual_total_loan?
    loan
  end

  def imported_loan_attributes(attrs, shg, member, created_by = nil)
    timestamp = Time.current

    {
      shg_id: shg.id,
      shg_member_id: member.id,
      product_id: cached_import_product(attrs[:product]).id,
      activity_id: cached_import_activity(attrs[:member_activity].presence || attrs[:activity]).id,
      loan_status_id: imported_loan_status(attrs).id,
      created_by_id: (created_by || import_crp(attrs) || @import_current_user).id,
      source_crp_identifier: attrs[:crp_identifier],
      source_crp_name: attrs[:crp_name],
      source_loan_status: imported_loan_status_label(attrs),
      source_interest_amount: attrs[:interest_amount].presence,
      source_total_payable: attrs[:total_payable].presence,
      source_principal_collect: attrs[:principal_collect].presence,
      source_interest_collect: attrs[:interest_collect].presence,
      source_paid: attrs[:paid_amount].presence,
      source_remaining: attrs[:remaining_amount].presence,
      geography_type: attrs[:geography_type],
      distribution_date: attrs[:distribution_date],
      loan_term_type: attrs[:loan_term_type],
      loan_term: attrs[:loan_term],
      principal_amount: attrs[:principal_amount],
      interest_percent: attrs[:interest_percent],
      interest_amount: imported_interest_amount(attrs),
      total_payable: imported_total_payable(attrs),
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def manual_import_totals?(attrs)
    attrs[:interest_percent].blank?
  end

  def imported_loan_status(attrs)
    status = imported_loan_status_label(attrs)
    return default_import_loan_status if status.blank?

    @import_loan_statuses[status.downcase] ||= LoanStatus.where("LOWER(code) = ? OR LOWER(name) = ?", status.downcase, status.downcase).first || default_import_loan_status
  end

  def imported_loan_status_label(attrs)
    status = attrs[:loan_status].to_s.strip
    total = imported_total_payable(attrs).to_d
    paid = attrs[:paid_amount].to_d
    remaining = attrs[:remaining_amount].to_d if attrs[:remaining_amount].present?

    return "Closed" if remaining == 0 || (total.positive? && paid >= total)
    return "Active" if remaining.to_d.positive? || paid <= 0

    status.presence || "Active"
  end

  def default_import_loan_status
    @default_import_loan_status ||= LoanStatus.default_active
  end

  def imported_interest_amount(attrs)
    interest_amount = attrs[:interest_amount].to_d
    return interest_amount if attrs[:interest_amount].present?

    total_payable = attrs[:total_payable].to_d
    return [ total_payable - attrs[:principal_amount].to_d, 0.to_d ].max if attrs[:total_payable].present?

    0.to_d
  end

  def imported_total_payable(attrs)
    return attrs[:total_payable].to_d if attrs[:total_payable].present?

    attrs[:principal_amount].to_d + imported_interest_amount(attrs)
  end

  def create_imported_summary_emi!(loan)
    paid_remaining = loan.source_paid.to_d
    timestamp = Time.current
    rows = loan.equal_installment_schedule.map do |emi|
      paid_amount = [ paid_remaining, emi[:due_amount].to_d ].min
      paid_remaining -= paid_amount

      {
        shg_loan_id: loan.id,
        installment_no: emi[:installment_no],
        due_date: emi[:due_date],
        principal_amount: emi[:principal_amount],
        interest_amount: emi[:interest_amount],
        due_amount: emi[:due_amount],
        paid_amount: paid_amount,
        paid_on: paid_amount.positive? ? Date.current : nil,
        status: imported_emi_status_for(emi[:due_date], emi[:due_amount], paid_amount),
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    ShgLoanEmi.insert_all!(rows) if rows.any?
  end

  def imported_summary_emi_attributes(attrs, loan_attributes)
    timestamp = loan_attributes[:created_at]
    paid_remaining = attrs[:paid_amount].to_d

    imported_equal_installment_schedule(loan_attributes).map do |emi|
      paid_amount = [ paid_remaining, emi[:due_amount].to_d ].min
      paid_remaining -= paid_amount

      {
        installment_no: emi[:installment_no],
        due_date: emi[:due_date],
        principal_amount: emi[:principal_amount],
        interest_amount: emi[:interest_amount],
        due_amount: emi[:due_amount],
        paid_amount: paid_amount,
        paid_on: paid_amount.positive? ? Date.current : nil,
        status: imported_emi_status_for(emi[:due_date], emi[:due_amount], paid_amount),
        created_at: timestamp,
        updated_at: timestamp
      }
    end
  end

  def insert_imported_loan_batch!(loan_batch, emi_batch)
    return if loan_batch.blank?

    inserted = ShgLoan.insert_all!(loan_batch, returning: %w[id])
    emi_rows = inserted.rows.flat_map.with_index do |row, index|
      emi_batch[index].map { |emi| emi.merge(shg_loan_id: row.first) }
    end
    ShgLoanEmi.insert_all!(emi_rows) if emi_rows.any?
  end

  def imported_equal_installment_schedule(loan_attributes)
    installments = loan_attributes[:loan_term].to_i
    return [] if installments <= 0

    total_due = loan_attributes[:total_payable].to_d
    principal_total = loan_attributes[:principal_amount].to_d
    interest_total = [ total_due - principal_total, loan_attributes[:interest_amount].to_d ].max
    principal_emi = principal_total / installments
    interest_emi = interest_total / installments
    due_emi = total_due / installments
    principal_allocated = 0.to_d
    interest_allocated = 0.to_d
    due_allocated = 0.to_d

    installments.times.map do |index|
      final_installment = index == installments - 1
      principal_component = final_installment ? principal_total - principal_allocated : principal_emi.round(2)
      interest_component = final_installment ? interest_total - interest_allocated : interest_emi.round(2)
      due_amount = final_installment ? total_due - due_allocated : due_emi.round(2)

      principal_allocated += principal_component
      interest_allocated += interest_component
      due_allocated += due_amount

      {
        installment_no: index + 1,
        due_date: loan_attributes[:distribution_date] + ((index + 1) * emi_interval_months_for(loan_attributes[:loan_term_type])).months,
        principal_amount: principal_component.round(2),
        interest_amount: interest_component.round(2),
        due_amount: due_amount.round(2)
      }
    end
  end

  def imported_emi_status_for(due_date, due_amount, paid_amount)
    return "paid" if paid_amount.to_d >= due_amount.to_d

    due_date < Date.current ? "overdue" : "pending"
  end

  def emi_interval_months_for(term_type)
    case term_type
    when "Quarterly" then 3
    when "Half Yearly" then 6
    when "Yearly" then 12
    else 1
    end
  end

  def import_crp(attrs)
    email = attrs[:crp_email].to_s.downcase
    return @import_crps[[ :email, email ]] ||= User.find_by(email: email) if email.present?

    identifier = attrs[:crp_identifier].to_s.strip
    if identifier.present?
      user = @import_crps[[ :login_id, identifier.downcase ]] ||= User.find_by(login_id: identifier.downcase)
      return user if user&.crp?

      if identifier.match?(/\A\d+\z/)
        user = @import_crps[[ :id, identifier ]] ||= User.find_by(id: identifier.to_i)
        return user if user&.crp?
      end
    end

    name = attrs[:crp_name].presence || identifier
    return if name.blank?

    @import_crps[[ :name, name.downcase ]] ||= @import_crp_users_by_name[name.downcase]
  end

  def apply_imported_payment(loan, paid_amount)
    payment = paid_amount.to_d
    return if payment <= 0

    loan.ensure_emi_schedule!
    touched_emi = false
    loan.shg_loan_emis.order(:installment_no).each do |emi|
      break if payment <= 0

      amount = [ payment, emi.remaining_amount ].min
      next if amount <= 0

      paid = [ emi.paid_amount.to_d + amount, emi.due_amount.to_d ].min
      emi.update_columns(
        paid_amount: paid,
        paid_on: paid.positive? ? Date.current : nil,
        status: imported_emi_status(emi, paid),
        updated_at: Time.current
      )
      payment -= amount
      touched_emi = true
    end

    sync_imported_loan_status!(loan) if touched_emi
  end

  def imported_emi_status(emi, paid)
    return "paid" if paid >= emi.due_amount.to_d

    emi.due_date < Date.current ? "overdue" : "pending"
  end

  def sync_imported_loan_status!(loan)
    loan.reload
    status =
      if loan.closed?
        LoanStatus.find_by(code: "CLOSED")
      elsif loan.shg_loan_emis.any?(&:overdue?)
        LoanStatus.find_by(code: "OVERDUE")
      else
        LoanStatus.default_active
      end

    loan.update_column(:loan_status_id, status.id) if status && loan.loan_status_id != status.id
  end

  def set_loan
    @loan = visible_shg_loans.find(params[:id])
  end

  def loan_params
    permitted = params.require(:shg_loan)
      .except(:block_id, :village_id)
      .permit(:shg_id, :shg_member_id, :product_id, :geography_type, :distribution_date, :loan_term_type, :loan_term, :principal_amount, :interest_percent)
    permitted[:activity_id] = visible_shg_members.find_by(id: permitted[:shg_member_id])&.activity_id || default_import_activity.id
    permitted
  end
end
