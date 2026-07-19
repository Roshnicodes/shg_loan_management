class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :logged_in?, :can_manage_records?, :can_approve_shg?, :readonly_admin?,
    :can_manage_users?, :can_manage_shg?, :can_manage_shg_member?, :can_approve_visit?, :can_manage_visit?,
    :can_bulk_delete_records?,
    :visible_states, :visible_districts, :visible_blocks, :visible_villages, :visible_shgs,
    :manageable_shgs, :visible_shg_members, :visible_visit_records

  DEFAULT_PAGE_SIZE = 50

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id] || cookies.signed[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    redirect_to login_path, alert: "Please sign in to continue." unless logged_in?
  end

  def readonly_admin?
    current_user&.readonly_admin?
  end

  def can_manage_records?
    logged_in? && !readonly_admin?
  end

  def can_bulk_delete_records?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def can_approve_shg?(shg = nil)
    return current_user&.approval_user? unless shg

    shg.approvable_by?(current_user)
  end

  def can_manage_users?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def can_manage_shg?(shg)
    return false unless can_manage_records? && shg
    return shg.created_by_id == current_user.id && (shg.draft? || shg.pending_dc?) if current_user&.crp?

    current_user&.admin? || current_user&.district_coordinator? || current_user&.assistant_admin?
  end

  def can_manage_shg_member?(member)
    can_manage_shg?(member&.shg)
  end

  def can_approve_visit?(visit = nil)
    return current_user&.approval_user? unless visit

    visit.approvable_by?(current_user)
  end

  def can_manage_visit?(visit)
    return false unless can_manage_records? && visit
    return false if visit.approved?
    return visit.created_by_id == current_user.id if current_user&.crp?
    return true if current_user&.admin?
    return true if current_user&.assistant_admin?
    return visit.created_by_id == current_user.id || visit.pending_dc? if current_user&.district_coordinator?

    false
  end

  def require_manage_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission for this action." unless can_manage_records?
  end

  def require_approval_permission!
    redirect_back fallback_location: shgs_path, alert: "You do not have approval permission." unless can_approve_shg?
  end

  def require_visit_approval_permission!
    redirect_back fallback_location: visit_records_path, alert: "You do not have visit approval permission." unless can_approve_visit?
  end

  def require_user_admin_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission for user management." unless can_manage_users?
  end

  def require_bulk_delete_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission to delete multiple records." unless can_bulk_delete_records?
  end

  def require_shg_manage_permission!
    redirect_back fallback_location: shgs_path, alert: "This SHG cannot be edited after DC approval." unless can_manage_shg?(@shg)
  end

  def require_shg_member_manage_permission!
    redirect_back fallback_location: shg_members_path, alert: "This SHG member cannot be edited after DC approval." unless can_manage_shg_member?(@member)
  end

  def require_visit_manage_permission!
    redirect_back fallback_location: visit_records_path, alert: "This visit cannot be edited at current approval stage." unless can_manage_visit?(@visit_record)
  end

  def visible_states
    return State.all if current_user&.admin? && current_user.state_id.blank?
    return State.all if current_user&.assistant_admin? && current_user.state_id.blank?
    return State.where(id: current_user.state_id) if current_user&.state_id.present?
    return State.joins(:districts).where(districts: { id: current_user.office_district_ids }).distinct if current_user&.office_district_ids.present?
    return State.joins(districts: :blocks).where(blocks: { id: current_user.office_block_ids }).distinct if current_user&.office_block_ids.present?
    return State.joins(districts: { blocks: :villages }).where(villages: { id: current_user.office_village_ids }).distinct if current_user&.office_village_ids.present?

    State.none
  end

  def visible_districts
    return District.all if current_user&.admin? && current_user.state_id.blank?
    return District.all if current_user&.assistant_admin? && current_user.state_id.blank?
    return District.where(id: current_user.office_district_ids) if current_user&.office_district_ids.present? && (current_user.crp? || current_user.district_coordinator?)
    return District.joins(:blocks).where(blocks: { id: current_user.office_block_ids }).distinct if current_user&.office_block_ids.present? && (current_user.crp? || current_user.district_coordinator?)
    return District.joins(blocks: :villages).where(villages: { id: current_user.office_village_ids }).distinct if current_user&.office_village_ids.present? && current_user.crp?
    return District.where(state_id: current_user.state_id) if current_user&.state_id.present?

    District.all
  end

  def visible_blocks
    return Block.all if current_user&.admin? && current_user.state_id.blank?
    return Block.all if current_user&.assistant_admin? && current_user.state_id.blank?
    return Block.where(id: current_user.office_block_ids) if current_user&.office_block_ids.present? && (current_user.crp? || current_user.district_coordinator?)
    return Block.joins(:villages).where(villages: { id: current_user.office_village_ids }).distinct if current_user&.office_village_ids.present? && current_user.crp?
    return Block.where(district_id: current_user.office_district_ids) if current_user&.office_district_ids.present?
    return Block.joins(:district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Block.all
  end

  def visible_villages
    return Village.all if current_user&.admin? && current_user.state_id.blank?
    return Village.all if current_user&.assistant_admin? && current_user.state_id.blank?
    return Village.where(id: current_user.office_village_ids) if current_user&.office_village_ids.present? && current_user.crp?
    return Village.where(block_id: current_user.office_block_ids) if current_user&.office_block_ids.present?
    return Village.joins(block: :district).where(districts: { id: current_user.office_district_ids }) if current_user&.office_district_ids.present?
    return Village.joins(block: :district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Village.all
  end

  def visible_shgs
    relation = Shg.includes(:state, :district, :block, :village)
    if current_user&.crp?
      loan_shg_ids = crp_visible_loan_scope.select(:shg_id)
      shg_scope = Shg.where(created_by: current_user).or(Shg.where(id: loan_shg_ids))
      location_scope = crp_visible_location_shgs
      shg_scope = shg_scope.or(location_scope) if location_scope.exists?
      return relation.where(id: shg_scope.select(:id))
    end
    return current_user.state_id.present? ? relation.where(state_id: current_user.state_id) : relation if current_user&.admin? || current_user&.assistant_admin?
    if current_user&.district_coordinator?
      return relation.none if current_user.office_district_ids.blank? && current_user.office_block_ids.blank?

      relation = relation.where(district_id: current_user.office_district_ids) if current_user.office_district_ids.present?
      relation = relation.where(block_id: current_user.office_block_ids) if current_user.office_block_ids.present?
      return relation.where.not(approval_status: "draft")
    end

    relation.none
  end

  def manageable_shgs
    relation = visible_shgs
    return relation.where(created_by: current_user, approval_status: %w[draft pending_dc]) if current_user&.crp?

    relation
  end

  def visible_shg_members
    relation = ShgMember.includes(:shg, :occupation)
    if current_user&.crp?
      loan_member_ids = crp_visible_loan_scope.select(:shg_member_id)
      return relation.where(shg_id: visible_shgs.select(:id)).or(relation.where(id: loan_member_ids))
    end

    relation.where(shg_id: visible_shgs.select(:id))
  end

  def visible_shg_loans
    relation = ShgLoan.includes(:shg, :shg_member, :product, :loan_status, :created_by)
    return relation.where(shg_id: visible_shgs.select(:id)).or(relation.merge(crp_visible_loan_scope)) if current_user&.crp?

    relation.where(shg_id: visible_shgs.select(:id))
  end

  def crp_visible_loan_scope
    login_id = current_user.login_id.to_s.downcase

    ShgLoan.where(created_by: current_user)
      .or(ShgLoan.where("LOWER(source_crp_identifier) = ?", login_id))
  end

  def visible_visit_records
    relation = VisitRecord.includes(:village, :shg, :shg_member, :product, :created_by, :dc_approved_by, :assistant_approved_by)
    return relation.where(created_by: current_user).or(relation.where(shg_id: visible_shgs.select(:id))) if current_user&.crp?
    return current_user.state_id.present? ? relation.joins(:shg).where(shgs: { state_id: current_user.state_id }) : relation if current_user&.admin? || current_user&.assistant_admin?
    if current_user&.district_coordinator?
      return relation.none if current_user.office_district_ids.blank? && current_user.office_block_ids.blank?

      relation = relation.joins(:shg)
      relation = relation.where(shgs: { district_id: current_user.office_district_ids }) if current_user.office_district_ids.present?
      relation = relation.where(shgs: { block_id: current_user.office_block_ids }) if current_user.office_block_ids.present?
      return relation
    end

    relation.none
  end

  def filter_states
    visible_states.order(:name)
  end

  def filter_districts
    visible_districts.order(:name)
  end

  def filter_blocks
    visible_blocks.order(:name)
  end

  def filter_villages
    visible_villages.order(:name)
  end

  def filter_crps
    return User.where(id: current_user.id).includes(:user_type).order(:name) if current_user&.crp?

    users = User.includes(:user_type).order(:name).select(&:crp?)
    users =
      if current_user&.admin? || current_user&.assistant_admin?
        users
      else
        users.select do |user|
          (user.office_district_ids & visible_districts.pluck(:id)).present? ||
            (user.office_block_ids & visible_blocks.pluck(:id)).present? ||
            (user.office_village_ids & visible_villages.pluck(:id)).present?
        end
      end

    filter_users_by_selected_location(users)
  end

  def filter_district_coordinators
    users = User.includes(:user_type).order(:name).select(&:district_coordinator?)
    filter_users_by_selected_location(users)
  end

  def apply_user_office_scope_to_shgs(relation, user)
    return relation.none unless user

    if user.office_village_ids.present?
      relation.where(village_id: user.office_village_ids)
    elsif user.office_block_ids.present?
      relation.where(block_id: user.office_block_ids)
    elsif user.office_district_ids.present?
      relation.where(district_id: user.office_district_ids)
    elsif user.state_id.present?
      relation.where(state_id: user.state_id)
    else
      relation.none
    end
  end

  def apply_user_office_scope_to_joined_shgs(relation, user)
    return relation.none unless user

    relation = relation.joins(:shg)
    if user.office_village_ids.present?
      relation.where(shgs: { village_id: user.office_village_ids })
    elsif user.office_block_ids.present?
      relation.where(shgs: { block_id: user.office_block_ids })
    elsif user.office_district_ids.present?
      relation.where(shgs: { district_id: user.office_district_ids })
    elsif user.state_id.present?
      relation.where(shgs: { state_id: user.state_id })
    else
      relation.none
    end
  end

  def crp_visible_location_shgs
    return Shg.none unless current_user&.crp?

    if current_user.office_village_ids.present?
      Shg.where(village_id: current_user.office_village_ids)
    elsif current_user.office_block_ids.present?
      Shg.where(block_id: current_user.office_block_ids)
    elsif current_user.office_district_ids.present?
      Shg.where(district_id: current_user.office_district_ids)
    else
      Shg.none
    end
  end

  def handle_record_not_found
    redirect_back fallback_location: dashboard_path, alert: "This record is not available for your login or was removed."
  end

  def disable_records(relation, ids)
    records = relation.where(id: Array(ids).compact_blank)
    disabled = 0
    skipped = 0

    records.find_each do |record|
      if record.respond_to?(:active=)
        record.update_columns(active: false, updated_at: Time.current)
        disabled += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      skipped += 1
    end

    { disabled: disabled, skipped: skipped }
  end

  def paginate_relation(relation, per_page: DEFAULT_PAGE_SIZE)
    @page = params[:page].to_i
    @page = 1 if @page < 1
    @per_page = per_page
    @total_count = relation.count
    @total_pages = (@total_count.to_f / @per_page).ceil
    @page = @total_pages if @total_pages.positive? && @page > @total_pages

    relation.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def filter_users_by_selected_location(users)
    filters = {
      state_id: params[:state_id].presence&.to_i,
      district_id: params[:district_id].presence&.to_i,
      block_id: params[:block_id].presence&.to_i,
      village_id: params[:village_id].presence&.to_i
    }
    return users if filters.values.compact.blank?

    users.select { |user| user_matches_selected_location?(user, filters) }
  end

  def user_matches_selected_location?(user, filters)
    return false if filters[:state_id].present? && !user_office_state_ids(user).include?(filters[:state_id])
    return false if filters[:district_id].present? && !user_office_district_ids(user).include?(filters[:district_id])
    return false if filters[:block_id].present? && !user_office_block_ids(user).include?(filters[:block_id])
    return false if filters[:village_id].present? && !user_office_village_ids(user).include?(filters[:village_id])

    true
  end

  def user_office_state_ids(user)
    ids = user.office_state_ids
    ids += District.where(id: user.office_district_ids).pluck(:state_id) if user.office_district_ids.present?
    ids += Block.joins(:district).where(id: user.office_block_ids).pluck("districts.state_id") if user.office_block_ids.present?
    ids += Village.joins(block: :district).where(id: user.office_village_ids).pluck("districts.state_id") if user.office_village_ids.present?
    ids.uniq
  end

  def user_office_district_ids(user)
    ids = user.office_district_ids
    ids += Block.where(id: user.office_block_ids).pluck(:district_id) if user.office_block_ids.present?
    ids += Village.joins(:block).where(id: user.office_village_ids).pluck("blocks.district_id") if user.office_village_ids.present?
    ids = District.where(state_id: user.office_state_ids).pluck(:id) if ids.blank? && user.office_state_ids.present?
    ids.uniq
  end

  def user_office_block_ids(user)
    return user.office_block_ids if user.office_block_ids.present?
    return Village.where(id: user.office_village_ids).pluck(:block_id).uniq if user.office_village_ids.present?

    district_ids = user_office_district_ids(user)
    return Block.where(district_id: district_ids).pluck(:id) if district_ids.present?

    []
  end

  def user_office_village_ids(user)
    return user.office_village_ids if user.office_village_ids.present?

    block_ids = user_office_block_ids(user)
    return Village.where(block_id: block_ids).pluck(:id) if block_ids.present?

    []
  end
end
