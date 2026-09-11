class LocationOptionsController < ApplicationController
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
    return render json: [] if params[:village_id].blank?

    shgs = visible_shgs.where(active: true)
    shgs = shgs.where(block_id: params[:block_id]) if params[:block_id].present?
    shgs = shgs.where(village_id: params[:village_id]) if params[:village_id].present?

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

  private

  def village_option(village)
    { id: village.id, text: village.name, block_id: village.block_id }
  end

  def shg_option(shg)
    {
      id: shg.id,
      text: shg.display_name,
      block_id: shg.block_id,
      village_id: shg.village_id
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
