require "csv"

class VisitRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_visit_record, only: %i[show edit update destroy approve return_for_correction reject]
  before_action :require_manage_permission!, only: %i[new create]
  before_action :require_visit_manage_permission!, only: %i[edit update destroy]
  before_action :require_visit_approval_permission!, only: %i[approve return_for_correction reject]
  before_action :require_bulk_delete_permission!, only: :bulk_destroy

  def index
    set_filter_options
    @visit_records = paginate_relation(filtered_visit_records.order(visit_date: :desc, created_at: :desc))
  end

  def export
    send_data visits_csv(filtered_visit_records.order(visit_date: :desc, created_at: :desc)),
      filename: "visit-records-#{Date.current}.csv",
      type: "text/csv; charset=utf-8"
  end

  def show; end

  def new
    @visit_record = VisitRecord.new(visit_date: Date.current)
  end

  def create
    @visit_record = VisitRecord.new(visit_record_params)
    @visit_record.created_by = current_user

    if @visit_record.save
      redirect_to visit_records_path, notice: "Visit entry saved successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @visit_record.update(visit_record_params)
      redirect_to visit_records_path, notice: "Visit entry updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @visit_record.destroy
    redirect_to visit_records_path, notice: "Visit entry deleted successfully."
  end

  def bulk_destroy
    result = bulk_destroy_records(filtered_visit_records, params[:ids])
    redirect_to visit_records_path, notice: "Visits deleted: #{result[:deleted]}, skipped: #{result[:skipped]}."
  end

  def approve
    return redirect_to(visit_records_path, alert: "This visit is not pending at your approval level.") unless @visit_record.approvable_by?(current_user)

    @visit_record.approve!(current_user)
    redirect_to visit_records_path, notice: @visit_record.approved? ? "Visit approved successfully." : "Visit sent to Assistant Admin approval."
  end

  def return_for_correction
    return redirect_to(visit_records_path, alert: "This visit is not pending at your approval level.") unless @visit_record.returnable_by?(current_user)

    @visit_record.return_for_correction!(current_user, params[:approval_remarks])
    redirect_to visit_records_path, notice: "Visit returned for correction."
  end

  def reject
    return redirect_to(visit_records_path, alert: "This visit is not pending at your approval level.") unless @visit_record.rejectable_by?(current_user)

    @visit_record.reject!(current_user, params[:approval_remarks])
    redirect_to visit_records_path, notice: "Visit rejected successfully."
  end

  private

  def set_filter_options
    users = User.includes(:user_type).order(:name)
    @crps = users.select(&:crp?)
    @district_coordinators = users.select(&:district_coordinator?)
    @assistant_admins = users.select(&:assistant_admin?)
    @states = State.order(:name)
    @districts = params[:state_id].present? ? District.where(state_id: params[:state_id]).order(:name) : District.order(:name)
    @blocks = params[:district_id].present? ? Block.where(district_id: params[:district_id]).order(:name) : Block.order(:name)
    @villages = params[:block_id].present? ? Village.where(block_id: params[:block_id]).order(:name) : Village.order(:name)
  end

  def filtered_visit_records
    visits = visible_visit_records
      .includes(:product, :created_by, :dc_approved_by, :assistant_approved_by, shg: [ :state, :district, :block, :village ])
      .with_attached_photo

    visits = apply_month_filter(visits)
    visits = visits.where(visit_date: params[:date_from]..) if params[:date_from].present?
    visits = visits.where(visit_date: ..params[:date_to]) if params[:date_to].present?
    visits = visits.joins(:shg).where(shgs: { state_id: params[:state_id] }) if params[:state_id].present?
    visits = visits.joins(:shg).where(shgs: { district_id: params[:district_id] }) if params[:district_id].present?
    visits = visits.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    visits = visits.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
    visits = visits.where(created_by_id: params[:crp_id]) if params[:crp_id].present? && can_filter_crp?
    visits = visits.where("visit_records.dc_approved_by_id = :id OR visit_records.created_by_id = :id", id: params[:dc_id]) if params[:dc_id].present? && can_filter_dc?
    visits = visits.where("visit_records.assistant_approved_by_id = :id OR visit_records.created_by_id = :id", id: params[:assistant_id]) if params[:assistant_id].present? && can_filter_assistant?
    visits
  end

  def apply_month_filter(visits)
    return visits unless params[:month].present?

    date = Date.strptime(params[:month], "%Y-%m")
    visits.where(visit_date: date.beginning_of_month..date.end_of_month)
  rescue Date::Error
    visits
  end

  def can_filter_crp?
    current_user&.district_coordinator? || current_user&.assistant_admin? || current_user&.admin?
  end

  def can_filter_dc?
    current_user&.assistant_admin? || current_user&.admin?
  end

  def can_filter_assistant?
    current_user&.admin?
  end

  def visits_csv(visits)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Visit Date", "State", "District", "Block", "Village", "SHG", "Member", "Loan No",
        "Aadhaar", "Mobile", "Product", "Purpose", "Observations", "Approval",
        "Created By", "DC Approval", "Assistant Approval", "Remarks"
      ]

      visits.each do |visit|
        csv << [
          visit.visit_date,
          visit.shg.state.name,
          visit.shg.district.name,
          visit.shg.block.name,
          visit.village.name,
          visit.shg.name,
          visit.shg_member.name,
          visit.shg_member.loan_no,
          visit.shg_member.aadhaar_no,
          visit.shg_member.mobile,
          visit.product&.name,
          visit.purpose,
          visit.observations,
          visit.approval_label,
          visit.created_by&.name,
          visit.dc_approved_by&.name,
          visit.assistant_approved_by&.name,
          visit.approval_remarks
        ]
      end
    end
  end

  def set_visit_record
    @visit_record = visible_visit_records.find(params[:id])
  end

  def visit_record_params
    params.require(:visit_record).permit(:village_id, :shg_id, :shg_member_id, :product_id, :visit_date, :purpose, :observations, :photo)
  end
end
