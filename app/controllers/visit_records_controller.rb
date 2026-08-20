require "csv"

class VisitRecordsController < ApplicationController
  VISIT_INDEX_PARAMS = %i[
    page q date_from date_to assistant_id dc_id crp_id
    state_id district_id block_id village_id shg_id approval_status month
  ].freeze

  helper_method :can_filter_visit_state_district_crp?

  before_action :authenticate_user!
  before_action :set_visit_record, only: %i[show edit update destroy disable approve return_for_correction reject]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_visit_manage_permission!, only: %i[edit update destroy disable]
  before_action :require_visit_approval_permission!, only: %i[approve return_for_correction reject]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

  def index
    set_filter_options
    @visit_records = paginate_relation(filtered_visit_records.order(visit_date: :desc, created_at: :desc))
  end

  def export
    stream_visits_csv(filtered_visit_records(include_attachments: false).order(visit_date: :desc, created_at: :desc))
  end

  def show; end

  def new
    @visit_record = VisitRecord.new(visit_date: Date.current)
  end

  def create
    @visit_record = VisitRecord.new(visit_record_params)
    @visit_record.created_by = current_user

    if @visit_record.valid? && (existing_visit = duplicate_visit_for(@visit_record))
      existing_visit.merge_submission!(@visit_record, current_user)
      attach_duplicate_photo(existing_visit, @visit_record)
      return redirect_to visit_records_path(visit_records_return_params), notice: "Visit entry updated successfully as #{existing_visit.visit_label}."
    end

    if @visit_record.save
      redirect_to visit_records_path(visit_records_return_params), notice: "Visit entry saved successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @visit_record.update(visit_record_params)
      redirect_to visit_records_path(visit_records_return_params), notice: "Visit entry updated successfully."
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
    @visit_record.update_columns(active: false, updated_at: Time.current)
    redirect_to visit_records_path(visit_records_return_params), notice: "Visit entry disabled successfully."
  end

  def bulk_disable
    result = disable_records(filtered_visit_records, params[:ids])
    redirect_to visit_records_path(visit_records_return_params), notice: "Visits disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  def approve
    return redirect_to(visit_records_path(visit_records_return_params), alert: "This visit is not pending at your approval level.") unless @visit_record.approvable_by?(current_user)

    @visit_record.approve!(current_user)
    redirect_to visit_records_path(visit_records_return_params), notice: @visit_record.approved? ? "Visit approved successfully." : "Visit sent to Assistant Admin approval."
  end

  def return_for_correction
    return redirect_to(visit_records_path(visit_records_return_params), alert: "This visit is not pending at your approval level.") unless @visit_record.returnable_by?(current_user)

    @visit_record.return_for_correction!(current_user, params[:approval_remarks])
    redirect_to visit_records_path(visit_records_return_params), notice: "Visit returned for correction."
  end

  def reject
    return redirect_to(visit_records_path(visit_records_return_params), alert: "This visit is not pending at your approval level.") unless @visit_record.rejectable_by?(current_user)

    @visit_record.reject!(current_user, params[:approval_remarks])
    redirect_to visit_records_path(visit_records_return_params), notice: "Visit rejected successfully."
  end

  private

  def set_filter_options
    if can_filter_visit_state_district_crp?
      @crps = limited_user_filter_records(filter_crps, params[:crp_id])
      @district_coordinators = limited_user_filter_records(filter_district_coordinators, params[:dc_id])
      @assistant_admins = limited_user_filter_records(users_with_role_codes("ASSIST_ADMIN", "ASSISTANT_ADMIN"), params[:assistant_id])
      @states = filter_states
      @districts = limited_filter_records(filter_districts_for_params, params[:district_id])
    end

    @blocks = limited_filter_records(filter_blocks_for_params, params[:block_id])
    @villages = limited_filter_records(filter_villages_for_params, params[:village_id])
    @shgs = limited_filter_records(visit_filter_shgs, params[:shg_id])
  end

  def filtered_visit_records(include_attachments: true)
    visits = visible_visit_records.where(active: true)
      .includes(:product, :shg_member, :created_by, :dc_approved_by, :assistant_approved_by, shg: [ :state, :district, :block, :village ])
    visits = visits.with_attached_photo if include_attachments

    visits = apply_month_filter(visits)
    visits = visits.where(visit_date: params[:date_from]..) if params[:date_from].present?
    visits = visits.where(visit_date: ..params[:date_to]) if params[:date_to].present?
    if can_filter_visit_state_district_crp?
      visits = visits.joins(:shg).where(shgs: { state_id: params[:state_id] }) if params[:state_id].present?
      visits = visits.joins(:shg).where(shgs: { district_id: params[:district_id] }) if params[:district_id].present?
      visits = visits.where(created_by_id: params[:crp_id]) if params[:crp_id].present?
      visits = apply_user_office_scope_to_joined_shgs(visits, User.includes(:user_type).find_by(id: params[:dc_id])) if params[:dc_id].present? && can_filter_dc?
      visits = visits.where("visit_records.assistant_approved_by_id = :id OR visit_records.created_by_id = :id", id: params[:assistant_id]) if params[:assistant_id].present? && can_filter_assistant?
    end
    visits = visits.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    visits = visits.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
    visits = visits.where(shg_id: params[:shg_id]) if params[:shg_id].present?
    visits = visits.where(approval_status: params[:approval_status]) if params[:approval_status].present?
    visits = search_visits(visits)
    deduplicate_visits_by_member(visits)
  end

  def search_visits(visits)
    query = params[:q].to_s.strip
    return visits if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    visits.left_joins(:shg_member, :product, :created_by, shg: [ :state, :district, :block, :village ])
      .where(
        [
          "CAST(visit_records.id AS TEXT) ILIKE :query",
          "CAST(visit_records.visit_date AS TEXT) ILIKE :query",
          "LOWER(visit_records.purpose) LIKE :query",
          "LOWER(visit_records.observations) LIKE :query",
          "LOWER(visit_records.approval_status) LIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(shg_members.loan_no) LIKE :query",
          "LOWER(products.name) LIKE :query",
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

  def apply_month_filter(visits)
    return visits unless params[:month].present?

    date = Date.strptime(params[:month], "%Y-%m")
    visits.where(visit_date: date.beginning_of_month..date.end_of_month)
  rescue Date::Error
    visits
  end

  def can_filter_visit_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def visit_filter_option_scope
    visible_visit_records.joins(:shg)
  end

  def visit_filter_crps
    crp_ids = filter_crps.map(&:id) & visit_filter_option_scope.distinct.pluck(:created_by_id)
    limited_filter_records(User.where(id: crp_ids).includes(:user_type).order(:name), params[:crp_id])
  end

  def visit_filter_shgs
    shgs = visible_shgs
    shgs = shgs.where(state_id: params[:state_id]) if params[:state_id].present?
    shgs = shgs.where(district_id: params[:district_id]) if params[:district_id].present?
    shgs = shgs.where(block_id: params[:block_id]) if params[:block_id].present?
    shgs = shgs.where(village_id: params[:village_id]) if params[:village_id].present?
    shgs.order(:name)
  end

  def can_filter_dc?
    current_user&.assistant_admin? || current_user&.admin?
  end

  def can_filter_assistant?
    current_user&.admin?
  end

  def stream_visits_csv(visits)
    stream_csv("visit-records-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "Visit Date", "Visit No.", "State", "District", "Block", "Village", "SHG", "Member", "Loan No",
        "Mobile", "Product", "Purpose", "Observations", "Approval",
        "Created By", "DC Approval", "Assistant Approval", "Remarks"
      ])

      visits.reorder(nil).find_each(batch_size: 1_000) do |visit|
        stream << CSV.generate_line([
          visit.visit_date,
          visit.visit_label,
          visit.shg.state.name,
          visit.shg.district.name,
          visit.shg.block.name,
          visit.village.name,
          visit.shg.name,
          visit.shg_member.name,
          visit.shg_member.loan_no,
          visit.shg_member.mobile,
          visit.product&.name,
          visit.purpose,
          visit.observations,
          visit.approval_label,
          visit.created_by&.name,
          visit.dc_approved_by&.name,
          visit.assistant_approved_by&.name,
          visit.approval_remarks
        ])
      end
    end
  end

  def set_visit_record
    @visit_record = visible_visit_records.find(params[:id])
  end

  def duplicate_visit_for(visit_record)
    VisitRecord.duplicate_of(visit_record).first
  end

  def attach_duplicate_photo(existing_visit, new_visit)
    return unless new_visit.photo.attached?

    existing_visit.photo.attach(new_visit.photo.blob)
  end

  def deduplicate_visits_by_member(visits)
    latest_visit_ids = visits
      .reselect("DISTINCT ON (visit_records.shg_member_id) visit_records.id")
      .reorder("visit_records.shg_member_id, visit_records.visit_number DESC, visit_records.visit_date DESC, visit_records.updated_at DESC, visit_records.id DESC")

    visits.where(id: latest_visit_ids)
  end

  def visit_record_params
    params.require(:visit_record).permit(:block_id, :village_id, :shg_id, :shg_member_id, :product_id, :visit_date, :purpose, :observations, :photo, :active)
  end

  def visit_records_return_params
    params.permit(*VISIT_INDEX_PARAMS).to_h
  end
end
