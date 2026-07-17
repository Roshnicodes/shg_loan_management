require "csv"

class ShgMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_member, only: %i[show edit update destroy]
  before_action :require_manage_permission!, only: %i[new create]
  before_action :require_shg_member_manage_permission!, only: %i[edit update destroy]
  before_action :require_bulk_delete_permission!, only: %i[destroy bulk_destroy]

  def index
    set_filter_options
    @members = paginate_relation(filtered_members.order(created_at: :desc))
  end

  def export
    set_filter_options
    send_data members_csv(filtered_members.order(created_at: :desc)),
      filename: "shg-members-#{Date.current}.csv",
      type: "text/csv; charset=utf-8"
  end

  def show; end

  def new
    @member = ShgMember.new(active: true)
  end

  def create
    @member = ShgMember.new(member_params)
    apply_default_occupation(@member)

    unless visible_shgs.exists?(id: @member.shg_id)
      @member.errors.add(:shg, "is not available for your login")
      return render :new, status: :unprocessable_entity
    end

    if @member.save
      redirect_to shg_members_path, notice: "SHG member saved successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @member.assign_attributes(member_params)
    apply_default_occupation(@member)
    unless visible_shgs.exists?(id: @member.shg_id)
      @member.errors.add(:shg, "is not available for your login")
      return render :edit, status: :unprocessable_entity
    end

    if @member.save
      redirect_to shg_members_path, notice: "SHG member updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @member.destroy
    redirect_to shg_members_path, notice: "SHG member deleted successfully."
  end

  def bulk_destroy
    result = bulk_destroy_records(visible_shg_members, params[:ids])
    redirect_to shg_members_path, notice: "SHG members deleted: #{result[:deleted]}, skipped: #{result[:skipped]}."
  end

  private

  def set_filter_options
    @states = State.order(:name)
    @districts = params[:state_id].present? ? District.where(state_id: params[:state_id]).order(:name) : District.order(:name)
    @blocks = params[:district_id].present? ? Block.where(district_id: params[:district_id]).order(:name) : Block.order(:name)
    @villages = params[:block_id].present? ? Village.where(block_id: params[:block_id]).order(:name) : Village.order(:name)
    @shgs = visible_shgs.order(:name)
    @crps = User.includes(:user_type).select(&:crp?).sort_by(&:name)
  end

  def filtered_members
    members = visible_shg_members.includes(shg: [ :state, :district, :block, :village, :created_by ])
    members = members.where(created_at: params[:date_from].to_date.beginning_of_day..) if params[:date_from].present?
    members = members.where(created_at: ..params[:date_to].to_date.end_of_day) if params[:date_to].present?
    members = members.where(shg_id: params[:shg_id]) if params[:shg_id].present?
    members = members.joins(:shg).where(shgs: { state_id: params[:state_id] }) if params[:state_id].present?
    members = members.joins(:shg).where(shgs: { district_id: params[:district_id] }) if params[:district_id].present?
    members = members.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    members = members.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
    members = members.joins(:shg).where(shgs: { created_by_id: params[:crp_id] }) if params[:crp_id].present?
    members
  rescue Date::Error
    visible_shg_members
  end

  def members_csv(members)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Member", "SHG", "Loan No", "Aadhaar", "Mobile", "Monthly HH Income",
        "State", "District", "Block", "Village", "Created At"
      ]

      members.each do |member|
        csv << [
          member.name,
          member.shg.name,
          member.loan_no,
          helpers.masked_aadhaar(member.aadhaar_no),
          member.mobile,
          member.monthly_income,
          member.shg.state.name,
          member.shg.district.name,
          member.shg.block.name,
          member.shg.village.name,
          member.created_at
        ]
      end
    end
  end

  def apply_default_occupation(member)
    member.occupation ||= Occupation.find_or_create_by!(name: "Imported")
  end

  def set_member
    @member = visible_shg_members.find(params[:id])
  end

  def member_params
    params.require(:shg_member).permit(:shg_id, :name, :gender, :dob, :mobile, :aadhaar_no, :loan_no, :monthly_income, :address, :active)
  end
end
