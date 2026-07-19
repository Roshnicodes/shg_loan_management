require "csv"

class ShgsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shg, only: %i[show edit update destroy disable approve return_for_correction reject]
  before_action :require_manage_permission!, only: %i[new create]
  before_action :require_shg_manage_permission!, only: %i[edit update destroy disable]
  before_action :require_approval_permission!, only: %i[approve return_for_correction reject]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

  def index
    set_filter_options
    @shgs = paginate_relation(filtered_shgs.order(created_at: :desc))
  end

  def export
    set_filter_options
    send_data shgs_csv(filtered_shgs.order(created_at: :desc)),
      filename: "shg-master-#{Date.current}.csv",
      type: "text/csv; charset=utf-8"
  end

  def show; end

  def new
    @shg = Shg.new(active: true)
  end

  def create
    @shg = Shg.new(shg_params)
    @shg.created_by = current_user
    if @shg.save
      redirect_to shgs_path, notice: "SHG registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @shg.update(shg_params)
      redirect_to shgs_path, notice: "SHG updated successfully."
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
    @shg.update_columns(active: false, updated_at: Time.current)
    redirect_to shgs_path, notice: "SHG disabled successfully."
  end

  def bulk_disable
    result = disable_records(visible_shgs, params[:ids])
    redirect_to shgs_path, notice: "SHGs disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  def approve
    return redirect_to(shgs_path, alert: "This SHG is not pending at your approval level.") unless @shg.approvable_by?(current_user)

    @shg.approve!(current_user)
    redirect_to shgs_path, notice: @shg.approved? ? "SHG approved successfully." : "SHG sent to Assistant Admin approval."
  end

  def return_for_correction
    return redirect_to(shgs_path, alert: "This SHG is not pending at your approval level.") unless @shg.returnable_by?(current_user)

    @shg.return_for_correction!(current_user, params[:approval_remarks])
    redirect_to shgs_path, notice: "SHG returned to CRP for correction."
  end

  def reject
    return redirect_to(shgs_path, alert: "This SHG is not pending at your approval level.") unless @shg.rejectable_by?(current_user)

    @shg.reject!(current_user, params[:approval_remarks])
    redirect_to shgs_path, notice: "SHG rejected successfully."
  end

  private

  def set_filter_options
    @states = filter_states
    @districts = filter_districts
    @blocks = filter_blocks
    @villages = filter_villages
    users = User.includes(:user_type).order(:name)
    @crps = filter_crps
    @district_coordinators = filter_district_coordinators
    @assistant_admins = users.select(&:assistant_admin?)
  end

  def filtered_shgs
    shgs = visible_shgs
      .includes(:created_by, :dc_approved_by, :assistant_approved_by, :state, :district, :block, :village)
      .with_attached_meeting_photo
      .with_attached_meeting_register
    shgs = shgs.where(linkage_date: params[:date_from]..) if params[:date_from].present?
    shgs = shgs.where(linkage_date: ..params[:date_to]) if params[:date_to].present?
    shgs = shgs.where(state_id: params[:state_id]) if params[:state_id].present?
    shgs = shgs.where(district_id: params[:district_id]) if params[:district_id].present?
    shgs = shgs.where(block_id: params[:block_id]) if params[:block_id].present?
    shgs = shgs.where(village_id: params[:village_id]) if params[:village_id].present?
    shgs = shgs.where(approval_status: params[:approval_status]) if params[:approval_status].present?
    shgs = shgs.where(created_by_id: params[:crp_id]) if params[:crp_id].present?
    if params[:dc_id].present? && (current_user&.assistant_admin? || current_user&.admin?)
      shgs = apply_user_office_scope_to_shgs(shgs, User.includes(:user_type).find_by(id: params[:dc_id]))
    end
    shgs = shgs.where(assistant_approved_by_id: params[:assistant_id]) if params[:assistant_id].present? && current_user&.admin?
    shgs
  end

  def shgs_csv(shgs)
    CSV.generate(headers: true) do |csv|
      csv << [
        "SHG", "State", "District", "Block", "Village", "Linkage Date",
        "Approval", "Created By", "DC Approval", "Assistant Approval", "Remarks"
      ]

      shgs.each do |shg|
        csv << [
          shg.name,
          shg.state.name,
          shg.district.name,
          shg.block.name,
          shg.village.name,
          shg.linkage_date,
          shg.approval_label,
          shg.created_by&.name,
          shg.dc_approved_by&.name,
          shg.assistant_approved_by&.name,
          shg.approval_remarks
        ]
      end
    end
  end

  def set_shg
    @shg = visible_shgs.find(params[:id])
  end

  def shg_params
    params.require(:shg).permit(:state_id, :district_id, :block_id, :village_id, :name, :linkage_date, :active, :meeting_register, :meeting_photo)
  end
end
