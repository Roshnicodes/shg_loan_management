class ApplicationController < ActionController::Base
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
    return State.all unless current_user&.state_id.present? && !current_user.assistant_admin? && !current_user.admin?

    State.where(id: current_user.state_id)
  end

  def visible_districts
    return District.all if current_user&.admin? || (current_user&.assistant_admin? && current_user.state_id.blank?)
    return District.where(id: current_user.district_id) if current_user&.district_id.present? && (current_user.crp? || current_user.district_coordinator?)
    return District.where(state_id: current_user.state_id) if current_user&.state_id.present?

    District.all
  end

  def visible_blocks
    return Block.all if current_user&.admin? || (current_user&.assistant_admin? && current_user.state_id.blank?)
    return Block.where(id: current_user.block_id) if current_user&.block_id.present? && current_user.crp?
    return Block.where(district_id: current_user.district_id) if current_user&.district_id.present?
    return Block.joins(:district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Block.all
  end

  def visible_villages
    return Village.all if current_user&.admin? || (current_user&.assistant_admin? && current_user.state_id.blank?)
    return Village.where(id: current_user.village_id) if current_user&.village_id.present? && current_user.crp?
    return Village.where(block_id: current_user.block_id) if current_user&.block_id.present?
    return Village.joins(block: :district).where(districts: { id: current_user.district_id }) if current_user&.district_id.present?
    return Village.joins(block: :district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Village.all
  end

  def visible_shgs
    relation = Shg.includes(:state, :district, :block, :village)
    return relation.where(created_by: current_user) if current_user&.crp?
    return relation if current_user&.admin? || current_user&.assistant_admin?
    return relation.where(district_id: current_user.district_id).where.not(approval_status: "draft") if current_user&.district_coordinator? && current_user.district_id.present?

    relation.none
  end

  def manageable_shgs
    relation = visible_shgs
    return relation.where(created_by: current_user, approval_status: %w[draft pending_dc]) if current_user&.crp?

    relation
  end

  def visible_shg_members
    ShgMember.includes(:shg, :occupation).where(shg_id: visible_shgs.select(:id))
  end

  def visible_shg_loans
    relation = ShgLoan.includes(:shg, :shg_member, :product, :loan_status, :created_by)
    return relation.where(created_by: current_user) if current_user&.crp?

    relation.where(shg_id: visible_shgs.select(:id))
  end

  def visible_visit_records
    relation = VisitRecord.includes(:village, :shg, :shg_member, :product, :created_by, :dc_approved_by, :assistant_approved_by)
    return relation.where(created_by: current_user) if current_user&.crp?
    return relation if current_user&.admin? || current_user&.assistant_admin?
    return relation.joins(:shg).where(shgs: { district_id: current_user.district_id }) if current_user&.district_coordinator? && current_user.district_id.present?

    relation.none
  end

  def bulk_destroy_records(relation, ids)
    records = relation.where(id: Array(ids).compact_blank)
    deleted = 0
    skipped = 0

    records.find_each do |record|
      if record.destroy
        deleted += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
      skipped += 1
    end

    { deleted: deleted, skipped: skipped }
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
end
