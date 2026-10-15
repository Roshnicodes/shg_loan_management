class LocationOptionsController < ApplicationController
  FILTER_REMOTE_OPTION_LIMIT = 10_000

  before_action :authenticate_user!

  def villages
    village_ids_with_active_shgs = visible_shgs.where(active: true).where.not(village_id: nil).select(:village_id)

    render json: visible_villages
      .where(id: village_ids_with_active_shgs)
      .where(block_id: params[:block_id])
      .order(:name)
      .map { |village| village_option(village) }
  end

  def shgs
    village_ids = filter_param_ids(:village_id)
    return render json: [] if village_ids.blank?

    shgs = visible_shgs
    shgs = shgs.where(active: true) unless params[:include_inactive] == "1"

    block_ids = filter_param_ids(:block_id)
    shgs = shgs.where(block_id: block_ids) if block_ids.present?
    shgs = shgs.where(village_id: village_ids)

    render json: shgs.order(:name).map { |shg| shg_option(shg) }
  end

  def members
    return render json: [] if params[:shg_id].blank?

    members = visible_shg_members.where(active: true).includes(:activity, :shg)
    members = members.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    members = members.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
    members = members.where(shg_id: params[:shg_id]) if params[:shg_id].present?
    members = members_available_for_loan(members) if params[:available_for_loan].present?

    render json: members.order(:name).map { |member| member_option(member) }
  end

  # Options for index-page filters, so a child filter (e.g. Village) can be
  # picked right after its parent (e.g. Block) without applying the form first.
  # A selected CRP or SHG also narrows the location filters above it to the
  # places where that CRP works or that SHG is.
  def filters
    state_ids = filter_param_ids(:state_id)
    district_ids = filter_param_ids(:district_id)
    block_ids = filter_param_ids(:block_id)
    village_ids = filter_param_ids(:village_id)
    crp_shgs = filter_crp_shgs(filter_param_ids(:crp_id))
    location_shgs = crp_shgs
    shg_ids = filter_param_ids(:shg_id)
    location_shgs = (location_shgs || visible_shgs).where(id: shg_ids) if shg_ids.present?

    states = filter_states
    districts = filter_districts_for_params
    blocks = filter_blocks_for_params
    villages = filter_villages_for_params
    if location_shgs
      states = states.where(id: location_shgs.select(:state_id))
      districts = districts.where(id: location_shgs.select(:district_id))
      blocks = blocks.where(id: location_shgs.select(:block_id))
      villages = villages.where(id: location_shgs.select(:village_id))
    end
    shgs = filter_shgs_for(state_ids, district_ids, block_ids, village_ids)
    shgs = shgs.where(id: crp_shgs.select(:id)) if crp_shgs

    render json: {
      states: states.limit(FILTER_REMOTE_OPTION_LIMIT).map { |state| { id: state.id, text: state.name } },
      districts: districts.limit(FILTER_REMOTE_OPTION_LIMIT).map { |district| district_filter_option(district) },
      blocks: blocks.includes(:district).limit(FILTER_REMOTE_OPTION_LIMIT).map { |block| block_filter_option(block) },
      villages: villages.includes(block: :district).limit(FILTER_REMOTE_OPTION_LIMIT).map { |village| village_filter_option(village) },
      shgs: shgs.includes(:village).limit(FILTER_REMOTE_OPTION_LIMIT).map { |shg| shg_filter_option(shg) }
    }
  end

  private

  # SHGs a CRP works with: created the SHG, gave its loans, or made its visits.
  def filter_crp_shgs(crp_ids)
    return if crp_ids.blank?

    login_ids = User.where(id: crp_ids).pluck(:login_id).compact_blank.map(&:downcase)
    loan_shg_ids = ShgLoan.where(created_by_id: crp_ids)
    loan_shg_ids = loan_shg_ids.or(ShgLoan.where("LOWER(source_crp_identifier) IN (?)", login_ids)) if login_ids.present?

    visible_shgs.where(
      "shgs.created_by_id IN (:crp_ids) OR shgs.id IN (:loan_shg_ids) OR shgs.id IN (:visit_shg_ids)",
      crp_ids: crp_ids,
      loan_shg_ids: loan_shg_ids.select(:shg_id),
      visit_shg_ids: VisitRecord.where(created_by_id: crp_ids).select(:shg_id)
    )
  end

  def filter_shgs_for(state_ids, district_ids, block_ids, village_ids)
    shgs = visible_shgs
    shgs = shgs.where(state_id: state_ids) if state_ids.present?
    shgs = shgs.where(district_id: district_ids) if district_ids.present?
    shgs = shgs.where(block_id: block_ids) if block_ids.present?
    shgs = shgs.where(village_id: village_ids) if village_ids.present?
    shgs.order(:name)
  end

  def district_filter_option(district)
    { id: district.id, text: district.name, state_id: district.state_id }
  end

  def block_filter_option(block)
    { id: block.id, text: block.name, district_id: block.district_id, state_id: block.district&.state_id }
  end

  def village_filter_option(village)
    district = village.block&.district
    { id: village.id, text: village.name, block_id: village.block_id, district_id: district&.id, state_id: district&.state_id }
  end

  def shg_filter_option(shg)
    {
      id: shg.id,
      text: shg.display_name,
      state_id: shg.state_id,
      district_id: shg.district_id,
      block_id: shg.block_id,
      village_id: shg.village_id,
      linkage_date: shg.linkage_date&.iso8601
    }
  end

  def village_option(village)
    { id: village.id, text: village.name, block_id: village.block_id }
  end

  def shg_option(shg)
    {
      id: shg.id,
      text: shg.display_name,
      block_id: shg.block_id,
      village_id: shg.village_id,
      linkage_date: shg.linkage_date&.iso8601
    }
  end

  def member_option(member)
    {
      id: member.id,
      text: member.name,
      block_id: member.shg.block_id,
      village_id: member.shg.village_id,
      shg_id: member.shg_id,
      group: member.shg.display_name,
      gender: member.gender,
      dob: member.dob,
      spouse_father_name: member.spouse_father_name,
      work_activity: member.work_activity_name,
      address: member.shg.borrower_address
    }
  end

  def members_available_for_loan(members)
    loaned_member_ids = ShgLoan.where(active: true)
    loaned_member_ids = loaned_member_ids.where.not(id: params[:current_loan_id]) if params[:current_loan_id].present?

    members.where.not(id: loaned_member_ids.select(:shg_member_id))
  end
end
