require "csv"
require "fileutils"
require "nokogiri"
require "rexml/document"
require "set"
require "zip"

class ShgLoansController < ApplicationController
  IMPORT_BATCH_SIZE = 10_000
  ImportMemberReference = Struct.new(:id, :aadhaar_no, :shg_id, :name, keyword_init: true)
  ImportShgReference = Struct.new(:id, :village_id, :name, :approved, keyword_init: true) do
    def approved? = approved
  end

  before_action :authenticate_user!
  before_action :set_loan, only: %i[show edit update destroy disable passbook]
  before_action :require_manage_permission!, only: %i[new create edit update destroy disable]
  before_action :require_loan_import_permission!, only: %i[new_import import]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

  def index
    set_filter_options
    @loan_imports = LoanImport.includes(:user).recent.limit(5) if can_manage_records?
    @loans = paginate_relation(filtered_loans.order(created_at: :desc))
  end

  def export
    send_data loans_csv(filtered_loans.order(created_at: :desc)),
      filename: "shg-loans-#{Date.current}.csv",
      type: "text/csv; charset=utf-8"
  end

  def new_import
    redirect_to shg_loans_path
  end

  def import
    file = params[:file]
    return redirect_to(shg_loans_path, alert: "Please select a CSV or Excel file.") unless file.present?

    loan_import = start_async_loan_import(file)
    redirect_to shg_loans_path, notice: "Loan import started in background. Import ##{loan_import.id} status will update here."
  rescue CSV::MalformedCSVError, Zip::Error, REXML::ParseException
    redirect_to shg_loans_path, alert: "Uploaded file is not a valid CSV or Excel file."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to shg_loans_path, alert: e.record.errors.full_messages.to_sentence
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
  end

  def create
    @loan = ShgLoan.new(loan_params)
    @loan.created_by = current_user

    unless loan_selection_available?(@loan)
      @loan.errors.add(:shg, "and member are not available for your login")
      return render :new, status: :unprocessable_entity
    end

    if @loan.save
      redirect_to shg_loans_path, notice: "SHG loan saved successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @loan.assign_attributes(loan_params)
    unless loan_selection_available?(@loan)
      @loan.errors.add(:shg, "and member are not available for your login")
      return render :edit, status: :unprocessable_entity
    end

    if @loan.save
      redirect_to shg_loans_path, notice: "SHG loan updated successfully."
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
    @loan.update_columns(active: false, updated_at: Time.current)
    redirect_to shg_loans_path, notice: "SHG loan disabled successfully."
  end

  def bulk_disable
    result = disable_records(filtered_loans, params[:ids])
    redirect_to shg_loans_path, notice: "SHG loans disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  private

  def require_loan_import_permission!
    redirect_back fallback_location: shg_loans_path, alert: "You do not have permission to import loan data." unless can_manage_records?
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

    run_loan_import_in_background(import.id, import_path.to_s, filename, current_user.id)
    import
  end

  def run_loan_import_in_background(import_id, path, filename, user_id)
    Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          import = LoanImport.find(import_id)
          import.update!(status: "running", started_at: Time.current)

          file = Struct.new(:path, :original_filename).new(path, filename)
          controller = self.class.new
          controller.define_singleton_method(:current_user) { User.find(user_id) }
          result = controller.send(:import_loans, file)

          import.update!(
            status: "completed",
            total_rows: result[:rows],
            total_loans: result[:loans],
            approved_shgs: result[:approved_shgs],
            skipped_rows: result[:skipped],
            error_message: result[:errors].join(" | ").presence,
            finished_at: Time.current
          )
        rescue StandardError => e
          LoanImport.where(id: import_id).update_all(
            status: "failed",
            error_message: e.message.truncate(1000),
            finished_at: Time.current,
            updated_at: Time.current
          )
          Rails.logger.error("Loan import ##{import_id} failed: #{e.class}: #{e.message}")
        ensure
          FileUtils.rm_f(path)
        end
      end
    end
  end

  def loan_selection_available?(loan)
    return false unless visible_shgs.exists?(id: loan.shg_id)
    return false unless visible_shg_members.where(shg_id: loan.shg_id).exists?(id: loan.shg_member_id)

    true
  end

  def set_filter_options
    @states = filter_states
    @districts = filter_districts
    @blocks = filter_blocks
    @villages = filter_villages
    @crps = filter_crps
  end

  def filtered_loans
    loans = visible_shg_loans
      .includes(:created_by, :loan_status, :product, :shg_loan_emis, :shg_member, shg: [ :state, :district, :block, :village ])

    loans = loans.where(distribution_date: params[:date_from]..) if params[:date_from].present?
    loans = loans.where(distribution_date: ..params[:date_to]) if params[:date_to].present?
    loans = loans.joins(:shg).where(shgs: { state_id: params[:state_id] }) if params[:state_id].present?
    loans = loans.joins(:shg).where(shgs: { district_id: params[:district_id] }) if params[:district_id].present?
    loans = loans.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    loans = loans.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
    loans = loans.where(created_by_id: params[:crp_id]) if params[:crp_id].present?
    loans = search_loans(loans)
    loans
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
          "LOWER(COALESCE(shg_loans.source_crp_identifier, '')) LIKE :query",
          "LOWER(COALESCE(shg_loans.source_crp_name, '')) LIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(COALESCE(shg_members.loan_no, '')) LIKE :query",
          "LOWER(COALESCE(shg_members.mobile, '')) LIKE :query",
          "LOWER(products.name) LIKE :query",
          "LOWER(loan_statuses.name) LIKE :query",
          "LOWER(states.name) LIKE :query",
          "LOWER(districts.name) LIKE :query",
          "LOWER(blocks.name) LIKE :query",
          "LOWER(villages.name) LIKE :query",
          "LOWER(COALESCE(users.name, '')) LIKE :query",
          "LOWER(COALESCE(users.login_id, '')) LIKE :query"
        ].join(" OR "),
        query: pattern
      ).distinct
  end

  def loans_csv(loans)
    CSV.generate(headers: true) do |csv|
      csv << [
        "SHG Name", "Member", "State", "District", "Block", "Village", "CRP ID",
        "CRPName", "Product", "Disbursement Date", "Loan Status",
        "Term Type", "Loan term", "Principal", "Annual Interest Percent",
        "Interest Amount", "Total Payable", "Principal Collected",
        "Interest collected", "Paid", "Remaining", "Mobile", "Aadhaar",
        "Monthly hh income"
      ]

      loans.each do |loan|
        csv << [
          loan.shg.name,
          loan.shg_member.name,
          loan.shg.state.name,
          loan.shg.district.name,
          loan.shg.block.name,
          loan.shg.village.name,
          loan_crp_identifier(loan),
          loan_crp_name(loan),
          loan.product.name,
          formatted_import_date(loan.distribution_date),
          loan_status_label(loan),
          loan.loan_term_type,
          loan.loan_term,
          loan.principal_amount,
          loan.interest_percent,
          loan_interest_amount(loan),
          loan_total_payable(loan),
          loan_principal_collect(loan),
          loan_interest_collect(loan),
          loan_paid_amount(loan),
          loan_remaining_amount(loan),
          loan.shg_member.mobile,
          helpers.masked_aadhaar(loan.shg_member.aadhaar_no),
          loan.shg_member.monthly_income
        ]
      end
    end
  end

  def loan_crp_identifier(loan)
    loan.source_crp_identifier.presence || loan.created_by_id
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
    loan.source_principal_collect.presence || loan.cumulative_principal_collected
  end

  def loan_interest_collect(loan)
    loan.source_interest_collect.presence || loan.cumulative_interest_collected
  end

  def loan_paid_amount(loan)
    loan.source_paid.presence || loan.total_paid
  end

  def loan_remaining_amount(loan)
    loan.source_remaining.presence || loan.remaining_amount
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

  helper_method :loan_crp_identifier, :loan_crp_name, :loan_status_label,
    :loan_interest_amount, :loan_total_payable, :loan_principal_collect,
    :loan_interest_collect, :loan_paid_amount, :loan_remaining_amount,
    :formatted_import_date

  def import_loans(file)
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
        end
      end
    end

    result
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
    return true if row.fields.all?(&:blank?)

    [ 0, 1, 2, 3, 4, 5 ].all? { |index| row.fields[index].blank? }
  end

  def initialize_import_context
    @import_current_user = current_user
    @import_states = {}
    @import_districts = {}
    @import_blocks = {}
    @import_villages = {}
    @import_shgs = {}
    @import_used_aadhaars = ShgMember.where.not(aadhaar_no: nil).pluck(:aadhaar_no).to_set
    @import_products = {}
    @import_activities = {}
    @import_occupations = {}
    @import_crps = {}
    @import_crp_users_by_name = User.includes(:user_type).select(&:crp?).index_by { |user| user.name.to_s.downcase }
    @import_loan_statuses = {}
    @next_import_shg_code_no = Shg.maximum(:id).to_i + 1
    @next_import_member_loan_no = next_import_member_loan_no
  end

  def next_import_member_loan_no
    last_number = ShgMember
      .where("loan_no LIKE ?", "#{ShgMember::LOAN_NO_PREFIX}-%")
      .pluck(:loan_no)
      .filter_map { |value| value.to_s.split("-").last.to_i if value.to_s.match?(/\A#{Regexp.escape(ShgMember::LOAN_NO_PREFIX)}-\d+\z/) }
      .max

    last_number.to_i + 1
  end

  def next_import_member_loan_number
    number = @next_import_member_loan_no
    @next_import_member_loan_no += 1
    "#{ShgMember::LOAN_NO_PREFIX}-#{number}"
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
    @import_products[normalized_name] ||= Product.where("LOWER(name) = ?", normalized_name).first || Product.create!(name: canonical_name)
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
      CSV.parse(import_file_content(file), headers: true).map do |row|
        SpreadsheetImportRow.new(row.headers, row.fields)
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
      gender: import_value(row, "gender"),
      dob: import_date(row, "dob", "date of birth"),
      aadhaar_no: import_aadhaar_number(row),
      mobile: import_digits(row, "mobile", "mobile no", "mobile_no", "phone", "phone number", "phone no", "phone_no", "contact", "contact no", "borrower phone number", indexes: [ 21, 22 ]),
      monthly_income: import_value(row, "monthly hh income", "monthly income", "monthly_income", "income", "member income", indexes: [ 23, 24 ]),
      address: import_value(row, "address"),
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

  def import_aadhaar_number(row)
    value = import_value(
      row,
      "aadhaar", "aadhaar no", "aadhaar number", "aadhaar card", "aadhaar card no", "aadhaar card number", "aadhaar_no", "aadhaar_number",
      "aadhar", "aadhar no", "aadhar number", "aadhar card", "aadhar card no", "aadhar card number", "aadhar_no", "aadhar_number",
      "borrower aadhaar", "borrower aadhaar no", "borrower aadhaar number", "member aadhaar", "member aadhaar no", "member aadhaar number",
      indexes: [ 22 ]
    )
    return normalized_masked_aadhaar(value) if value.to_s.match?(/x/i)

    digits = normalized_import_identifier(value)
    digits.length == 12 ? digits : nil
  end

  def normalized_masked_aadhaar(value)
    digits = value.to_s.gsub(/\D/, "")
    return if digits.length != 4

    "XXXX-XXXX-#{digits}"
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
    rows = xlsx_sheet_rows(file)
    header_index = rows.index { |fields| fields.any?(&:present?) }
    return [] unless header_index

    headers = rows[header_index]
    rows[(header_index + 1)..].to_a.map { |fields| SpreadsheetImportRow.new(headers, fields) }
  end

  def xlsx_sheet_rows(file)
    Zip::File.open(file.path) do |xlsx|
      shared_strings = xlsx_shared_strings(xlsx)
      style_formats = xlsx_style_formats(xlsx)
      sheet_entry = xlsx.glob("xl/worksheets/sheet*.xml").min_by(&:name)
      return [] unless sheet_entry

      rows = []
      fields = nil
      cell_column = nil
      cell_type = nil
      cell_style = nil
      value = +""
      inline_text = +""
      in_value = false
      in_text = false

      Nokogiri::XML::Reader(sheet_entry.get_input_stream.read).each do |node|
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
            rows << fields.map { |field| field.to_s.strip } if fields
            fields = nil
          end
        end
      end

      rows
    end
  end

  def xlsx_shared_strings(xlsx)
    entry = xlsx.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    strings = []
    current = nil
    in_text = false

    Nokogiri::XML::Reader(entry.get_input_stream.read).each do |node|
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
    rows = processed_rows.map do |processed|
      attrs = processed.fetch(:attrs)
      shg = cached_import_shg(attrs, processed.fetch(:village))

      {
        shg_id: shg.id,
        occupation_id: cached_import_occupation(attrs[:occupation]).id,
        name: attrs[:member],
        loan_no: next_import_member_loan_number,
        gender: attrs[:gender],
        dob: attrs[:dob],
        aadhaar_no: unique_import_aadhaar(attrs[:aadhaar_no]),
        mobile: attrs[:mobile],
        monthly_income: attrs[:monthly_income].presence,
        address: attrs[:address],
        active: true,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    return if rows.blank?

    inserted = ShgMember.insert_all!(rows, returning: %w[id aadhaar_no shg_id name])
    inserted.rows.each_with_index do |row, index|
      data = inserted.columns.zip(row).to_h
      processed_rows[index][:member] = ImportMemberReference.new(
        id: data.fetch("id"),
        aadhaar_no: data["aadhaar_no"],
        shg_id: data.fetch("shg_id"),
        name: data.fetch("name")
      )
      @import_used_aadhaars << data["aadhaar_no"] if data["aadhaar_no"].present?
    end
  end

  def unique_import_aadhaar(aadhaar_no)
    aadhaar = aadhaar_no.presence
    return if aadhaar.blank? || @import_used_aadhaars.include?(aadhaar)

    @import_used_aadhaars << aadhaar
    aadhaar
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
      activity_id: cached_import_activity(attrs[:activity]).id,
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
    params.require(:shg_loan)
      .permit(:shg_id, :shg_member_id, :product_id, :loan_status_id, :geography_type, :distribution_date, :loan_term_type, :loan_term, :principal_amount, :interest_percent)
      .merge(activity_id: default_import_activity.id)
  end
end
