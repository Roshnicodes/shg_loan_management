require "csv"

class ShgMembersController < ApplicationController
  helper_method :can_filter_member_state_district_crp?

  MEMBER_INDEX_PARAMS = %i[
    page q date_from date_to crp_id
    state_id district_id block_id village_id shg_id
  ].freeze
  MEMBER_PREFILL_PARAMS = %i[
    shg_id block_id village_id gender monthly_income work_activity active
  ].freeze
  MEMBER_PREFILL_SESSION_KEY = :shg_member_prefill_params

  before_action :authenticate_user!
  before_action -> { restore_persistent_index_params(:shg_members_index_params, :shg_members_path, MEMBER_INDEX_PARAMS) }, only: :index
  before_action :set_member_form_prefill, only: %i[new create]
  before_action :set_member, only: %i[show edit update destroy activate disable]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_shg_member_manage_permission!, only: %i[edit update destroy activate disable]
  before_action :require_bulk_delete_permission!, only: %i[destroy activate disable bulk_destroy bulk_activate bulk_disable]

  def index
    set_filter_options
    @can_add_member = can_create_records? && visible_shgs.exists?
    @members = paginate_relation(filtered_members.order(created_at: :desc))
  end

  def export
    stream_members_csv(filtered_members.order(created_at: :desc))
  end

  def show; end

  def new
    @member = ShgMember.new(active: true)
    apply_member_prefill(@member)
  end

  def create
    @member = ShgMember.new(member_params)
    apply_default_occupation(@member)

    unless member_location_selection_available?(@member)
      @member.errors.add(:shg, "is not available for your login")
      return render :new, status: :unprocessable_entity
    end

    sync_member_activity(@member)

    if @member.save
      store_member_prefill
      if add_another_member?
        redirect_to new_shg_member_path(member_prefill_redirect_params), notice: "SHG member saved successfully. Add another member."
      else
        redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG member saved successfully."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @member.assign_attributes(member_params)
    apply_default_occupation(@member)
    unless member_location_selection_available?(@member)
      @member.errors.add(:shg, "is not available for your login")
      return render :edit, status: :unprocessable_entity
    end

    sync_member_activity(@member)

    if @member.save
      redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG member updated successfully."
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
    @member.update_columns(active: true, updated_at: Time.current)
    redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG member activated successfully."
  end

  def disable
    ActiveRecord::Base.transaction do
      @member.update_columns(active: false, updated_at: Time.current)
      disable_member_loans([ @member.id ])
    end
    redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG member disabled successfully."
  end

  def bulk_activate
    result = activate_records(visible_shg_members, params[:ids])
    redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG members activated: #{result[:activated]}, skipped: #{result[:skipped]}."
  end

  def bulk_disable
    member_ids = Array(params[:ids]).compact_blank
    members = visible_shg_members.where(id: member_ids)
    disabled = 0

    ActiveRecord::Base.transaction do
      disabled = members.where(active: true).update_all(active: false, updated_at: Time.current)
      disable_member_loans(members.select(:id))
    end

    result = { disabled: disabled, skipped: member_ids.size - members.count }
    redirect_to results_redirect_path(:shg_members_path, MEMBER_INDEX_PARAMS), notice: "SHG members disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  private

  def set_filter_options
    if can_filter_member_state_district_crp?
      @states = filter_states
      @districts = limited_filter_records(filter_districts_for_params, filter_param_values(:district_id))
      @crps = limited_user_filter_records(filter_crps, filter_param_values(:crp_id))
    end

    @blocks = limited_filter_records(filter_blocks_for_params, filter_param_values(:block_id))
    @villages = limited_filter_records(filter_villages_for_params, filter_param_values(:village_id))
    @shgs = limited_filter_records(member_filter_shgs, filter_param_values(:shg_id))
  end

  def set_member_form_prefill
    @member_form_prefill = member_form_prefill_params
  end

  def member_form_prefill_params
    saved_prefill = session[MEMBER_PREFILL_SESSION_KEY].is_a?(Hash) ? session[MEMBER_PREFILL_SESSION_KEY].slice(*MEMBER_PREFILL_PARAMS.map(&:to_s)) : {}
    index_prefill = {
      "shg_id" => filter_param_value(:shg_id),
      "block_id" => filter_param_value(:block_id),
      "village_id" => filter_param_value(:village_id)
    }.compact_blank

    merge_member_prefill(saved_prefill, index_prefill, submitted_member_prefill_params)
  end

  def merge_member_prefill(saved_prefill, index_prefill, submitted_prefill)
    prefill = saved_prefill.dup
    prefill.except!("village_id", "shg_id") if index_prefill["block_id"].present? && index_prefill["block_id"] != prefill["block_id"]
    prefill.except!("shg_id") if index_prefill["village_id"].present? && index_prefill["village_id"] != prefill["village_id"]

    prefill.merge(index_prefill).merge(submitted_prefill)
  end

  def submitted_member_prefill_params
    return {} unless params[:shg_member].respond_to?(:permit)

    params.require(:shg_member).permit(*MEMBER_PREFILL_PARAMS).to_h.compact_blank
  end

  def apply_member_prefill(member)
    attributes = @member_form_prefill.slice("shg_id", "gender", "monthly_income", "work_activity", "active")
    if attributes["shg_id"].present?
      shg = visible_shgs.find_by(id: attributes["shg_id"])
      attributes.delete("shg_id") if shg.blank? ||
        (@member_form_prefill["block_id"].present? && shg.block_id.to_s != @member_form_prefill["block_id"].to_s) ||
        (@member_form_prefill["village_id"].present? && shg.village_id.to_s != @member_form_prefill["village_id"].to_s)
    end

    member.assign_attributes(attributes)
  end

  def store_member_prefill
    prefill = submitted_member_prefill_params
    prefill.present? ? session[MEMBER_PREFILL_SESSION_KEY] = prefill : session.delete(MEMBER_PREFILL_SESSION_KEY)
  end

  def add_another_member?
    params[:add_another].present?
  end

  def member_prefill_redirect_params
    preserved_index_params(MEMBER_INDEX_PARAMS).merge(shg_member: session[MEMBER_PREFILL_SESSION_KEY])
  end

  def filtered_members
    members = member_rows_scope.includes(:activity, shg: [ :state, :district, :block, :village, :created_by ])
    members = members.where(created_at: params[:date_from].to_date.beginning_of_day..) if params[:date_from].present?
    members = members.where(created_at: ..params[:date_to].to_date.end_of_day) if params[:date_to].present?
    shg_ids = filter_param_ids(:shg_id)
    members = members.where(shg_id: shg_ids) if shg_ids.present?
    if can_filter_member_state_district_crp?
      state_ids = filter_param_ids(:state_id)
      district_ids = filter_param_ids(:district_id)
      crp_ids = filter_param_ids(:crp_id)
      members = members.joins(:shg).where(shgs: { state_id: state_ids }) if state_ids.present?
      members = members.joins(:shg).where(shgs: { district_id: district_ids }) if district_ids.present?
      members = members.joins(:shg).where(shgs: { created_by_id: crp_ids }) if crp_ids.present?
    end
    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    members = members.joins(:shg).where(shgs: { block_id: block_ids }) if block_ids.present?
    members = members.joins(:shg).where(shgs: { village_id: village_ids }) if village_ids.present?
    members = search_members(members)
    members
  rescue Date::Error
    member_rows_scope
  end

  def member_rows_scope
    visible_shg_members
  end

  def member_filter_option_scope
    member_rows_scope.joins(:shg)
  end

  def member_filter_crps
    crp_ids = filter_crps.map(&:id) & member_filter_option_scope.distinct.pluck("shgs.created_by_id")
    limited_filter_records(User.where(id: crp_ids).includes(:user_type).order(:name), params[:crp_id])
  end

  def member_filter_shgs
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

  def can_filter_member_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
  end

  def search_members(members)
    query = params[:q].to_s.strip
    return members if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    members.left_joins(:activity, shg: [ :state, :district, :block, :village ])
      .where(
        [
          "CAST(shg_members.id AS TEXT) ILIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(shg_members.spouse_father_name) LIKE :query",
          "LOWER(shg_members.work_activity) LIKE :query",
          "LOWER(shg_members.aadhaar_no) LIKE :query",
          "LOWER(shg_members.loan_no) LIKE :query",
          "LOWER(shg_members.mobile) LIKE :query",
          "LOWER(activities.name) LIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(states.name) LIKE :query",
          "LOWER(districts.name) LIKE :query",
          "LOWER(blocks.name) LIKE :query",
          "LOWER(villages.name) LIKE :query"
        ].join(" OR "),
        query: pattern
      ).distinct
  end

  def stream_members_csv(members)
    stream_csv("shg-members-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([
        "Member", "Spouse/Father Name", "SHG", "Loan No", "Aadhaar Number",
        "Work/Activity", "Date of Birth", "Mobile", "Monthly HH Income",
        "Office Location", "Borrower Short Address", "State", "District", "Block", "Village", "Created At"
      ])

      members.reorder(nil).find_each(batch_size: 1_000) do |member|
        stream << CSV.generate_line([
          member.name,
          member.spouse_father_name,
          member.shg.name,
          member.loan_no,
          member.aadhaar_no,
          member.work_activity_name,
          member.dob,
          member.mobile,
          member.monthly_income,
          member.shg.office_location,
          member.shg.borrower_short_address,
          member.shg.state.name,
          member.shg.district.name,
          member.shg.block.name,
          member.shg.village.name,
          member.created_at
        ])
      end
    end
  end

  def apply_default_occupation(member)
    member.occupation ||= Occupation.find_or_create_by!(name: "Imported")
  end

  def member_location_selection_available?(member)
    shg = visible_shgs.find_by(id: member.shg_id)
    return false unless shg

    selection = params[:shg_member] || {}
    block_id = selection[:block_id].presence || selection["block_id"].presence
    village_id = selection[:village_id].presence || selection["village_id"].presence

    return false if block_id.present? && shg.block_id.to_s != block_id.to_s
    return false if village_id.present? && shg.village_id.to_s != village_id.to_s

    true
  end

  def sync_member_activity(member)
    member.work_activity = member.work_activity.to_s.squish
    if member.work_activity.present?
      member.activity = Activity.where("LOWER(name) = ?", member.work_activity.downcase).first || Activity.create!(name: member.work_activity)
    else
      member.activity = nil
      member.work_activity = nil
    end
  end

  def disable_member_loans(member_ids)
    ShgLoan.where(shg_member_id: member_ids, active: true).update_all(active: false, updated_at: Time.current)
  end

  def set_member
    @member = visible_shg_members.find(params[:id])
  end

  def member_params
    params.require(:shg_member).permit(:shg_id, :name, :spouse_father_name, :gender, :dob, :mobile, :monthly_income, :work_activity, :aadhaar_no, :active)
  end
end
