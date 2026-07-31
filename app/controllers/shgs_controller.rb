require "csv"

class ShgsController < ApplicationController
  helper_method :can_filter_shg_state_district_crp?

  before_action :authenticate_user!
  before_action :set_shg, only: %i[show edit update destroy disable approve return_for_correction reject]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_shg_manage_permission!, only: %i[edit update destroy disable]
  before_action :require_approval_permission!, only: %i[approve return_for_correction reject]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

  def index
    set_filter_options
    shgs = filtered_shgs
    @meeting_attachment_counts = meeting_attachment_counts_for(shgs)
    @shgs = paginate_relation(shgs.order(created_at: :desc))
  end

  def export
    stream_shgs_csv(filtered_shgs.order(created_at: :desc))
  end

  def show; end

  def new
    @shg = Shg.new(active: true)
    apply_default_location(@shg)
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
    if can_filter_shg_state_district_crp?
      @states = filter_states
      @districts = limited_filter_records(filter_districts_for_params, params[:district_id])
      @crps = limited_user_filter_records(filter_crps, params[:crp_id])
      @district_coordinators = limited_user_filter_records(filter_district_coordinators, params[:dc_id])
      @assistant_admins = limited_user_filter_records(users_with_role_codes("ASSIST_ADMIN", "ASSISTANT_ADMIN"), params[:assistant_id])
    end

    @blocks = limited_filter_records(filter_blocks_for_params, params[:block_id])
    @villages = limited_filter_records(filter_villages_for_params, params[:village_id])
  end

  def filtered_shgs(include_attachments: true)
    shgs = visible_shgs
      .includes(:created_by, :dc_approved_by, :assistant_approved_by, :state, :district, :block, :village)
    if include_attachments
      shgs = shgs
        .with_attached_meeting_photo
        .with_attached_meeting_register
    end
    shgs = shgs.where(linkage_date: params[:date_from]..) if params[:date_from].present?
    shgs = shgs.where(linkage_date: ..params[:date_to]) if params[:date_to].present?
    if can_filter_shg_state_district_crp?
      shgs = shgs.where(state_id: params[:state_id]) if params[:state_id].present?
      shgs = shgs.where(district_id: params[:district_id]) if params[:district_id].present?
      shgs = shgs.where(created_by_id: params[:crp_id]) if params[:crp_id].present?
      if params[:dc_id].present?
        shgs = apply_user_office_scope_to_shgs(shgs, User.includes(:user_type).find_by(id: params[:dc_id]))
      end
      shgs = shgs.where(assistant_approved_by_id: params[:assistant_id]) if params[:assistant_id].present? && current_user&.admin?
    end
    shgs = shgs.where(block_id: params[:block_id]) if params[:block_id].present?
    shgs = shgs.where(village_id: params[:village_id]) if params[:village_id].present?
    shgs = shgs.where(approval_status: params[:approval_status]) if params[:approval_status].present?
    shgs = search_shgs(shgs)
    shgs
  end

  def shg_filter_option_scope
    visible_shgs
  end

  def can_filter_shg_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def shg_filter_crps
    crp_ids = filter_crps.map(&:id) & shg_filter_option_scope.distinct.pluck(:created_by_id)
    limited_filter_records(User.where(id: crp_ids).includes(:user_type).order(:name), params[:crp_id])
  end

  def search_shgs(shgs)
    query = params[:q].to_s.strip
    return shgs if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    shgs.left_joins(:state, :district, :block, :village, :created_by)
      .where(
        [
          "CAST(shgs.id AS TEXT) ILIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(shgs.shg_code) LIKE :query",
          "LOWER(shgs.approval_status) LIKE :query",
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

  def stream_shgs_csv(shgs)
    stream_csv("shg-master-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "SHG", "State", "District", "Block", "Village", "Linkage Date",
        "Approval", "Meeting Photo Uploaded", "Meeting Register Uploaded",
        "Meeting Photo Download", "Meeting Register Download",
        "Created By", "DC Approval", "Assistant Approval", "Remarks"
      ])

      shgs.reorder(nil).find_each(batch_size: 1_000) do |shg|
        stream << CSV.generate_line([
          shg.name,
          shg.state.name,
          shg.district.name,
          shg.block.name,
          shg.village.name,
          shg.linkage_date,
          shg.approval_label,
          shg.meeting_photo.attached? ? "Yes" : "No",
          shg.meeting_register.attached? ? "Yes" : "No",
          attachment_download_url(shg.meeting_photo),
          attachment_download_url(shg.meeting_register),
          shg.created_by&.name,
          shg.dc_approved_by&.name,
          shg.assistant_approved_by&.name,
          shg.approval_remarks
        ])
      end
    end
  end

  def attachment_download_url(attachment)
    return nil unless attachment.attached?

    rails_blob_url(
      attachment,
      disposition: "attachment",
      host: request.host_with_port,
      protocol: request.protocol
    )
  end

  def meeting_attachment_counts_for(shgs)
    total = shgs.reselect(:id).distinct.count
    photo_uploaded = shgs.joins(:meeting_photo_attachment).reselect(:id).distinct.count
    register_uploaded = shgs.joins(:meeting_register_attachment).reselect(:id).distinct.count

    {
      total: total,
      photo_uploaded: photo_uploaded,
      photo_missing: total - photo_uploaded,
      register_uploaded: register_uploaded,
      register_missing: total - register_uploaded
    }
  end

  def set_shg
    @shg = visible_shgs.find(params[:id])
  end

  def apply_default_location(shg)
    return unless current_user&.crp? || current_user&.district_coordinator?
    return if shg.state_id.present? || shg.district_id.present? || shg.block_id.present? || shg.village_id.present?

    district = District.includes(:state).find_by(id: current_user.office_district_ids.first)
    if district
      shg.district = district
      shg.state = district.state
      return
    end

    block = Block.includes(:district).find_by(id: current_user.office_block_ids.first)
    if block
      shg.district = block.district
      shg.state = block.district.state
      return
    end

    village = Village.includes(block: :district).find_by(id: current_user.office_village_ids.first)
    if village
      shg.district = village.block.district
      shg.state = village.block.district.state
      return
    end

    shg.state_id = current_user.state_id if current_user.state_id.present?
  end

  def shg_params
    params.require(:shg).permit(:state_id, :district_id, :block_id, :village_id, :name, :linkage_date, :active, :meeting_register, :meeting_photo)
  end
end
