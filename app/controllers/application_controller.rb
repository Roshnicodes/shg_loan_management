class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :logged_in?, :can_manage_records?, :can_approve_shg?, :readonly_admin?,
    :can_view_users?, :can_view_admin_records?, :can_manage_users?, :can_manage_shg?, :can_manage_shg_member?, :can_approve_visit?, :can_manage_visit?,
    :can_manage_shg_loan?, :can_bulk_delete_records?, :can_create_records?, :can_create_location_records?, :can_import_loan_data?,
    :visible_states, :visible_districts, :visible_blocks, :visible_villages, :visible_shgs,
    :manageable_shgs, :visible_shg_members, :visible_visit_records, :with_results_anchor,
    :filter_param_values, :filter_param_ids, :filter_param_value

  DEFAULT_PAGE_SIZE = 30
  FILTER_OPTION_LIMIT = 250
  RESULTS_ANCHOR = "results"

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

  def can_create_records?
    can_manage_records? && (current_user&.crp? || current_user&.district_coordinator?)
  end

  def can_create_location_records?
    can_manage_records? && (current_user&.admin? || current_user&.assistant_admin?)
  end

  def can_import_loan_data?
    can_manage_records? && (current_user&.admin? || current_user&.assistant_admin? || current_user&.district_coordinator? || current_user&.crp?)
  end

  def can_bulk_delete_records?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def can_approve_shg?(shg = nil)
    return current_user&.approval_user? unless shg

    shg.approvable_by?(current_user)
  end

  def can_view_users?
    current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
  end

  def can_view_admin_records?
    can_view_users?
  end

  def can_manage_users?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def can_manage_shg?(shg)
    return false unless can_manage_records? && shg
    return crp_can_manage_shg?(shg) if current_user&.crp?

    current_user&.admin? || current_user&.district_coordinator? || current_user&.assistant_admin?
  end

  def can_manage_shg_member?(member)
    can_manage_shg?(member&.shg)
  end

  def can_manage_shg_loan?(loan)
    return false unless can_manage_records? && loan
    return loan.created_by_id == current_user.id || can_manage_shg?(loan.shg) if current_user&.crp?

    current_user&.admin? || current_user&.assistant_admin? || current_user&.district_coordinator?
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

  def require_create_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission to add new records." unless can_create_records?
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

  def require_user_view_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission to view user records." unless can_view_users?
  end

  def require_admin_record_view_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission to view master records." unless can_view_admin_records?
  end

  def require_bulk_delete_permission!
    redirect_back fallback_location: dashboard_path, alert: "You do not have permission to disable multiple records." unless can_bulk_delete_records?
  end

  def require_shg_manage_permission!
    redirect_back fallback_location: shgs_path, alert: "This SHG is not editable for your login." unless can_manage_shg?(@shg)
  end

  def require_shg_member_manage_permission!
    redirect_back fallback_location: shg_members_path, alert: "This SHG member is not editable for your login." unless can_manage_shg_member?(@member)
  end

  def require_visit_manage_permission!
    redirect_back fallback_location: visit_records_path, alert: "This visit cannot be edited at current approval stage." unless can_manage_visit?(@visit_record)
  end

  def visible_states
    return State.all if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    return State.where(id: current_user.state_id) if current_user&.state_id.present?
    return State.joins(:districts).where(districts: { id: current_user.office_district_ids }).distinct if current_user&.office_district_ids.present?
    return State.joins(districts: :blocks).where(blocks: { id: current_user.office_block_ids }).distinct if current_user&.office_block_ids.present?
    return State.joins(districts: { blocks: :villages }).where(villages: { id: current_user.office_village_ids }).distinct if current_user&.office_village_ids.present?

    State.none
  end

  def visible_districts
    return District.all if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    return District.where(id: current_user.office_district_ids) if current_user&.office_district_ids.present? && (current_user.crp? || current_user.district_coordinator?)
    return District.joins(:blocks).where(blocks: { id: current_user.office_block_ids }).distinct if current_user&.office_block_ids.present? && (current_user.crp? || current_user.district_coordinator?)
    return District.joins(blocks: :villages).where(villages: { id: current_user.office_village_ids }).distinct if current_user&.office_village_ids.present? && current_user.crp?
    return District.where(state_id: current_user.state_id) if current_user&.state_id.present?

    District.all
  end

  def visible_blocks
    return Block.all if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    return Block.where(district_id: current_user.office_district_ids) if current_user&.district_coordinator? && current_user.office_district_ids.present?
    return crp_visible_blocks if current_user&.crp?
    return Block.where(district_id: current_user.office_district_ids) if current_user&.office_district_ids.present?
    return Block.joins(:district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Block.all
  end

  def visible_villages
    return Village.all if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    return crp_visible_villages if current_user&.crp?
    return Village.joins(block: :district).where(districts: { id: current_user.office_district_ids }) if current_user&.district_coordinator? && current_user.office_district_ids.present?
    return Village.where(block_id: current_user.office_block_ids) if current_user&.office_block_ids.present?
    return Village.joins(block: :district).where(districts: { id: current_user.office_district_ids }) if current_user&.office_district_ids.present?
    return Village.joins(block: :district).where(districts: { state_id: current_user.state_id }) if current_user&.state_id.present?

    Village.all
  end

  def visible_shgs
    relation = Shg.includes(:state, :district, :block, :village)
    if current_user&.crp?
      return relation.where(id: crp_visible_shg_scope.select(:id))
    end
    return relation if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    if current_user&.district_coordinator?
      return relation.none if current_user.office_district_ids.blank? && current_user.office_block_ids.blank?

      if current_user.office_district_ids.present?
        relation = relation.where(district_id: current_user.office_district_ids)
      elsif current_user.office_block_ids.present?
        relation = relation.where(block_id: current_user.office_block_ids)
      end
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

  def crp_can_manage_shg?(shg)
    shg.created_by_id == current_user.id || visible_shgs.exists?(id: shg.id)
  end

  def visible_visit_records
    relation = VisitRecord.includes(:village, :shg, :shg_member, :product, :created_by, :dc_approved_by, :assistant_approved_by)
    return relation.where(created_by: current_user).or(relation.where(shg_id: visible_shgs.select(:id))) if current_user&.crp?
    return relation if current_user&.admin? || current_user&.assistant_admin? || readonly_admin?
    if current_user&.district_coordinator?
      return relation.none if current_user.office_district_ids.blank? && current_user.office_block_ids.blank?

      relation = relation.joins(:shg)
      if current_user.office_district_ids.present?
        relation = relation.where(shgs: { district_id: current_user.office_district_ids })
      elsif current_user.office_block_ids.present?
        relation = relation.where(shgs: { block_id: current_user.office_block_ids })
      end
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

  def filter_districts_for_params
    districts = filter_districts
    state_ids = filter_param_ids(:state_id)
    districts = districts.where(state_id: state_ids) if state_ids.present?
    districts
  end

  def filter_blocks_for_params
    blocks = filter_blocks
    state_ids = filter_param_ids(:state_id)
    district_ids = filter_param_ids(:district_id)
    blocks = blocks.joins(:district).where(districts: { state_id: state_ids }) if state_ids.present?
    blocks = blocks.where(district_id: district_ids) if district_ids.present?
    blocks
  end

  def filter_villages_for_params
    villages = filter_villages
    block_ids = filter_param_ids(:block_id)
    district_ids = filter_param_ids(:district_id)
    state_ids = filter_param_ids(:state_id)
    if block_ids.present?
      villages = villages.where(block_id: block_ids)
    elsif district_ids.present?
      villages = villages.joins(:block).where(blocks: { district_id: district_ids })
    elsif state_ids.present?
      villages = villages.joins(block: :district).where(districts: { state_id: state_ids })
    end
    villages
  end

  def filter_crps
    return User.where(id: current_user.id).includes(:user_type).order(:name) if current_user&.crp?

    users = users_with_role_codes("CRP")
    users =
      if current_user&.admin? || current_user&.assistant_admin?
        users
      elsif readonly_admin?
        users
      else
        users.to_a.select do |user|
          (user.office_district_ids & visible_districts.pluck(:id)).present? ||
            (user.office_block_ids & visible_blocks.pluck(:id)).present? ||
            (user.office_village_ids & visible_villages.pluck(:id)).present?
        end
      end

    filter_users_by_selected_location(users)
  end

  def filter_district_coordinators
    users = users_with_role_codes("DIST_COORDINATOR", "DISTRICT_COORDINATOR")
    filter_users_by_selected_location(users)
  end

  def users_with_role_codes(*codes)
    User.joins(:user_type)
      .includes(:user_type)
      .where("UPPER(user_types.code) IN (?)", codes.map(&:upcase))
      .order(:name)
  end

  def apply_user_office_scope_to_shgs(relation, user)
    return relation.none unless user

    if user.crp?
      relation.where(id: crp_visible_shg_scope_for(user).select(:id))
    elsif user.district_coordinator? && user.office_district_ids.present?
      relation.where(district_id: user.office_district_ids)
    elsif user.office_village_ids.present?
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
    if user.crp?
      relation.where(shgs: { id: crp_visible_shg_scope_for(user).select(:id) })
    elsif user.district_coordinator? && user.office_district_ids.present?
      relation.where(shgs: { district_id: user.office_district_ids })
    elsif user.office_village_ids.present?
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

  def apply_users_office_scope_to_shgs(relation, users)
    users = Array(users).compact
    return relation.none if users.blank?

    shg_ids = users.flat_map { |user| apply_user_office_scope_to_shgs(Shg.all, user).reselect(:id).pluck(:id) }.uniq
    shg_ids.present? ? relation.where(id: shg_ids) : relation.none
  end

  def apply_users_office_scope_to_joined_shgs(relation, users)
    users = Array(users).compact
    return relation.none if users.blank?

    shg_ids = users.flat_map { |user| apply_user_office_scope_to_shgs(Shg.all, user).reselect(:id).pluck(:id) }.uniq
    shg_ids.present? ? relation.joins(:shg).where(shgs: { id: shg_ids }) : relation.none
  end

  def crp_visible_location_shgs
    return Shg.none unless current_user&.crp?

    crp_visible_location_shgs_for(current_user)
  end

  def crp_visible_shg_scope
    return Shg.none unless current_user&.crp?

    crp_visible_shg_scope_for(current_user)
  end

  def crp_visible_shg_scope_for(user)
    return Shg.none unless user&.crp?

    login_id = user.login_id.to_s.downcase
    loan_shg_ids = ShgLoan
      .where(created_by: user)
      .or(ShgLoan.where("LOWER(source_crp_identifier) = ?", login_id))
      .where.not(shg_id: nil)
      .select(:shg_id)

    Shg.where(created_by: user)
      .or(Shg.where(id: loan_shg_ids))
      .or(crp_visible_location_shgs_for(user))
  end

  def crp_visible_blocks
    shg_block_ids = crp_visible_shg_scope.where.not(block_id: nil).select(:block_id)
    mapped_village_block_ids = Village.where(id: current_user.office_village_ids).select(:block_id)
    blocks = Block.none
    if crp_district_wide_location_scope?
      blocks = blocks.or(Block.where(district_id: current_user.office_district_ids))
    end

    blocks
      .or(Block.where(id: shg_block_ids))
      .or(Block.where(id: current_user.office_block_ids))
      .or(Block.where(id: mapped_village_block_ids))
      .distinct
  end

  def crp_visible_villages
    shg_village_ids = crp_visible_shg_scope.where.not(village_id: nil).select(:village_id)
    district_block_ids = Block.where(district_id: current_user.office_district_ids).select(:id)
    villages = Village.none
    villages = villages.or(Village.where(block_id: district_block_ids)) if crp_district_wide_location_scope?

    villages
      .or(Village.where(id: shg_village_ids))
      .or(Village.where(id: current_user.office_village_ids))
      .or(Village.where(block_id: current_user.office_block_ids))
      .distinct
  end

  def crp_district_wide_location_scope?
    current_user.office_district_ids.present? &&
      current_user.office_block_ids.blank? &&
      current_user.office_village_ids.blank?
  end

  def crp_visible_location_shgs_for(user)
    return Shg.none unless user&.crp?

    if user.office_village_ids.present?
      Shg.where(village_id: user.office_village_ids)
    elsif user.office_block_ids.present?
      Shg.where(block_id: user.office_block_ids)
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

  def activate_records(relation, ids)
    records = relation.where(id: Array(ids).compact_blank)
    activated = 0
    skipped = 0

    records.find_each do |record|
      if record.respond_to?(:active=)
        record.update_columns(active: true, updated_at: Time.current)
        activated += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      skipped += 1
    end

    { activated: activated, skipped: skipped }
  end

  def paginate_relation(relation, per_page: DEFAULT_PAGE_SIZE)
    @page = params[:page].to_i
    @page = 1 if @page < 1
    @per_page = per_page
    @total_count = nil
    @total_pages = nil

    records = relation.offset((@page - 1) * @per_page).limit(@per_page + 1).to_a
    @has_next_page = records.size > @per_page
    page_records = records.first(@per_page)
    @page_item_count = page_records.size
    page_records
  end

  def restore_persistent_index_params(session_key, path_helper, permitted_keys)
    if params[:clear_filters].present?
      session.delete(session_key)
      redirect_to public_send(path_helper)
      return
    end

    permitted_key_names = permitted_keys.map(&:to_s)
    if (request.query_parameters.keys & permitted_key_names).present?
      index_params = sliced_request_params(permitted_keys)
      index_params.present? ? session[session_key] = index_params : session.delete(session_key)
      return
    end

    saved_params = session[session_key]
    return if saved_params.blank?

    flash.keep
    redirect_to public_send(path_helper, saved_params)
  end

  def preserved_index_params(permitted_keys)
    sliced_request_params(permitted_keys)
  end

  def results_redirect_path(path_helper, permitted_keys)
    with_results_anchor(public_send(path_helper, preserved_index_params(permitted_keys)))
  end

  def with_results_anchor(path)
    path = path.to_s
    return path if path.include?("#")

    "#{path}##{RESULTS_ANCHOR}"
  end

  def stream_csv(filename)
    headers["Content-Type"] = "text/csv; charset=utf-8"
    headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment",
      filename: filename
    )
    headers["Cache-Control"] = "no-cache"
    headers["X-Accel-Buffering"] = "no"
    headers.delete("Content-Length")

    self.response_body = Enumerator.new do |stream|
      yield stream
    ensure
      stream.close if stream.respond_to?(:close)
    end
  end

  def limited_filter_records(relation, selected_id = nil, limit: FILTER_OPTION_LIMIT)
    records = relation.limit(limit).to_a
    selected_ids = Array(selected_id).compact_blank.map(&:to_s)
    return records if selected_ids.blank?

    missing_ids = selected_ids - records.map { |record| record.id.to_s }
    return records if missing_ids.blank?

    records + relation.klass.where(id: missing_ids).to_a
  end

  def limited_user_filter_records(users, selected_id = nil, limit: FILTER_OPTION_LIMIT)
    records = users.first(limit)
    selected_ids = Array(selected_id).compact_blank.map(&:to_s)
    return records if selected_ids.blank?

    missing_ids = selected_ids - records.map { |user| user.id.to_s }
    return records if missing_ids.blank?

    records + User.includes(:user_type).where(id: missing_ids).to_a
  end

  def filter_users_by_selected_location(users)
    filters = {
      state_ids: filter_param_ids(:state_id),
      district_ids: filter_param_ids(:district_id),
      block_ids: filter_param_ids(:block_id),
      village_ids: filter_param_ids(:village_id)
    }
    return users if filters.values.all?(&:blank?)

    users.select { |user| user_matches_selected_location?(user, filters) }
  end

  def user_matches_selected_location?(user, filters)
    return false if filters[:state_ids].present? && (user_office_state_ids(user) & filters[:state_ids]).blank?
    return false if filters[:district_ids].present? && (user_office_district_ids(user) & filters[:district_ids]).blank?
    return false if filters[:block_ids].present? && (user_office_block_ids(user) & filters[:block_ids]).blank?
    return false if filters[:village_ids].present? && (user_office_village_ids(user) & filters[:village_ids]).blank?

    true
  end

  def filter_param_values(key)
    Array(params[key]).compact_blank.map(&:to_s)
  end

  def filter_param_ids(key)
    filter_param_values(key).filter_map do |value|
      Integer(value, exception: false)
    end.reject(&:zero?)
  end

  def filter_param_value(key)
    filter_param_values(key).first
  end

  def sliced_request_params(permitted_keys)
    key_names = permitted_keys.map(&:to_s)
    params.to_unsafe_h.slice(*key_names).transform_values do |value|
      value.is_a?(Array) ? value.compact_blank : value
    end.compact_blank
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
    return Block.where(district_id: user.office_district_ids).pluck(:id) if user.district_coordinator? && user.office_district_ids.present?
    return user.office_block_ids if user.office_block_ids.present?
    return Village.where(id: user.office_village_ids).pluck(:block_id).uniq if user.office_village_ids.present?

    district_ids = user_office_district_ids(user)
    return Block.where(district_id: district_ids).pluck(:id) if district_ids.present?

    []
  end

  def user_office_village_ids(user)
    return Village.joins(block: :district).where(districts: { id: user.office_district_ids }).pluck(:id) if user.district_coordinator? && user.office_district_ids.present?
    return user.office_village_ids if user.office_village_ids.present?

    block_ids = user_office_block_ids(user)
    return Village.where(block_id: block_ids).pluck(:id) if block_ids.present?

    []
  end
end
