require "csv"

class ShgsController < ApplicationController
  helper_method :can_filter_shg_state_district_crp?

  SHG_INDEX_PARAMS = %i[
    page q date_from date_to assistant_id dc_id crp_id
    state_id district_id block_id village_id approval_status
  ].freeze

  before_action :authenticate_user!
  before_action -> { restore_persistent_index_params(:shgs_index_params, :shgs_path, SHG_INDEX_PARAMS) }, only: :index
  before_action :set_shg, only: %i[show edit update destroy activate disable approve return_for_correction reject emi_collections update_emi_collections]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_shg_manage_permission!, only: %i[edit update destroy activate disable]
  before_action :require_create_permission!, only: %i[update_emi_collections]
  before_action :require_approval_permission!, only: %i[approve return_for_correction reject]
  before_action :require_bulk_delete_permission!, only: %i[destroy activate disable bulk_destroy bulk_activate bulk_disable]

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

  def emi_collections
    prepare_group_emi_collections
  end

  def new
    @shg = Shg.new(active: true)
    apply_default_location(@shg)
  end

  def create
    @shg = Shg.new(shg_params)
    @shg.created_by = current_user
    if @shg.save
      redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @shg.update(shg_params)
      redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG updated successfully."
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

  def activate
    @shg.update_columns(active: true, updated_at: Time.current)
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG activated successfully."
  end

  def disable
    @shg.update_columns(active: false, updated_at: Time.current)
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG disabled successfully."
  end

  def bulk_activate
    result = activate_records(visible_shgs, params[:ids])
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHGs activated: #{result[:activated]}, skipped: #{result[:skipped]}."
  end

  def bulk_disable
    result = disable_records(visible_shgs, params[:ids])
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHGs disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  def approve
    return redirect_to(results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), alert: "This SHG is not pending at your approval level.") unless @shg.approvable_by?(current_user)
    if current_user&.district_coordinator? && !@shg.ready_for_approval?
      return redirect_to(results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), alert: "At least one active SHG member loan is required before DC approval.")
    end

    if current_user&.district_coordinator? && !@shg.product_ready_for_approval?
      return redirect_to(results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), alert: "Product Type is mandatory for every active loan before DC approval.")
    end

    @shg.approve!(current_user)
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: @shg.approved? ? "SHG approved successfully." : "SHG sent to Assistant Admin approval."
  end

  def return_for_correction
    return redirect_to(results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), alert: "This SHG is not pending at your approval level.") unless @shg.returnable_by?(current_user)

    @shg.return_for_correction!(current_user, params[:approval_remarks])
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG returned to CRP for correction."
  end

  def reject
    return redirect_to(results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), alert: "This SHG is not pending at your approval level.") unless @shg.rejectable_by?(current_user)

    @shg.reject!(current_user, params[:approval_remarks])
    redirect_to results_redirect_path(:shgs_path, SHG_INDEX_PARAMS), notice: "SHG rejected successfully."
  end

  def update_emi_collections
    emis = group_emi_scope.index_by(&:id)
    updated = 0

    params.fetch(:emis, {}).each do |emi_id, values|
      amount = values[:paid_amount].presence || values["paid_amount"].presence
      next if amount.blank?

      emi = emis[emi_id.to_i]
      next unless emi

      payment = amount.to_d
      next unless payment.positive?

      emi.mark_paid!([ payment, emi.remaining_amount ].min)
      updated += 1
    end

    redirect_to emi_collections_shg_path(@shg, request.query_parameters.slice(*SHG_INDEX_PARAMS.map(&:to_s))), notice: "EMI collections updated: #{updated}."
  end

  private

  def set_filter_options
    if can_filter_shg_state_district_crp?
      @states = filter_states
      @districts = limited_filter_records(filter_districts_for_params, filter_param_values(:district_id))
      @crps = limited_user_filter_records(filter_crps, filter_param_values(:crp_id))
      @district_coordinators = limited_user_filter_records(filter_district_coordinators, filter_param_values(:dc_id))
      @assistant_admins = limited_user_filter_records(users_with_role_codes("ASSIST_ADMIN", "ASSISTANT_ADMIN"), filter_param_values(:assistant_id))
    end

    @blocks = limited_filter_records(filter_blocks_for_params, filter_param_values(:block_id))
    @villages = limited_filter_records(filter_villages_for_params, filter_param_values(:village_id))
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
      state_ids = filter_param_ids(:state_id)
      district_ids = filter_param_ids(:district_id)
      crp_ids = filter_param_ids(:crp_id)
      dc_ids = filter_param_ids(:dc_id)
      assistant_ids = filter_param_ids(:assistant_id)
      shgs = shgs.where(state_id: state_ids) if state_ids.present?
      shgs = shgs.where(district_id: district_ids) if district_ids.present?
      shgs = shgs.where(created_by_id: crp_ids) if crp_ids.present?
      shgs = apply_users_office_scope_to_shgs(shgs, User.includes(:user_type).where(id: dc_ids)) if dc_ids.present?
      shgs = shgs.where(assistant_approved_by_id: assistant_ids) if assistant_ids.present? && (current_user&.admin? || readonly_admin?)
    end
    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    approval_statuses = filter_param_values(:approval_status) & Shg::APPROVAL_STATUSES
    shgs = shgs.where(block_id: block_ids) if block_ids.present?
    shgs = shgs.where(village_id: village_ids) if village_ids.present?
    shgs = shgs.where(approval_status: approval_statuses) if approval_statuses.present?
    shgs = search_shgs(shgs)
    shgs
  end

  def shg_filter_option_scope
    visible_shgs
  end

  def can_filter_shg_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
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
          "LOWER(shgs.office_location) LIKE :query",
          "LOWER(shgs.borrower_short_address) LIKE :query",
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
        "SHG", "SHG Code", "Office Location", "Borrower Short Address",
        "State", "District", "Block", "Village", "Linkage Date",
        "Approval", "Meeting Photo Uploaded", "Meeting Register Uploaded",
        "Meeting Photo Download", "Meeting Register Download",
        "Created By", "DC Approval", "Assistant Approval", "Remarks"
      ])

      shgs.reorder(nil).find_each(batch_size: 1_000) do |shg|
        stream << CSV.generate_line([
          shg.name,
          shg.shg_code,
          shg.office_location,
          shg.borrower_short_address,
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

  def prepare_group_emi_collections
    @group_emi_records = group_emi_scope
    @group_emi_summary = {
      loans: @shg.shg_loans.where(active: true).count,
      pending_emis: @group_emi_records.count { |emi| emi.remaining_amount.positive? },
      due_amount: @group_emi_records.sum(&:due_amount),
      paid_amount: @group_emi_records.sum(&:paid_amount),
      remaining_amount: @group_emi_records.sum(&:remaining_amount)
    }
  end

  def group_emi_scope
    @shg.shg_loans.where(active: true).includes(:shg_member, :loan_status).find_each { |loan| loan.ensure_emi_schedule! }

    ShgLoanEmi
      .joins(shg_loan: :shg_member)
      .includes(shg_loan: [ :shg_member, :product, :loan_status ])
      .where(shg_loans: { shg_id: @shg.id, active: true })
      .order(:due_date, :installment_no, "shg_members.name")
      .to_a
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
    params.require(:shg).permit(:state_id, :district_id, :block_id, :village_id, :name, :office_location, :borrower_short_address, :linkage_date, :active, :meeting_register, :meeting_photo)
  end
end
