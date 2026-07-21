require "csv"

class ShgMembersController < ApplicationController
  helper_method :can_filter_member_state_district_crp?

  before_action :authenticate_user!
  before_action :set_member, only: %i[show edit update destroy disable]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_shg_member_manage_permission!, only: %i[edit update destroy disable]
  before_action :require_bulk_delete_permission!, only: %i[destroy disable bulk_destroy bulk_disable]

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
    disable
  end

  def bulk_destroy
    bulk_disable
  end

  def disable
    @member.update_columns(active: false, updated_at: Time.current)
    redirect_to shg_members_path, notice: "SHG member disabled successfully."
  end

  def bulk_disable
    result = disable_records(visible_shg_members, params[:ids])
    redirect_to shg_members_path, notice: "SHG members disabled: #{result[:disabled]}, skipped: #{result[:skipped]}."
  end

  private

  def set_filter_options
    if can_filter_member_state_district_crp?
      @states = State.where(id: member_filter_option_scope.select("shgs.state_id")).order(:name)
      @districts = District.where(id: member_filter_option_scope.select("shgs.district_id")).order(:name)
      @crps = member_filter_crps
    end

    @blocks = Block.where(id: member_filter_option_scope.select("shgs.block_id")).order(:name)
    @villages = Village.where(id: member_filter_option_scope.select("shgs.village_id")).order(:name)
    @shgs = Shg.where(id: member_filter_option_scope.select(:shg_id)).order(:name)
  end

  def filtered_members
    members = member_rows_scope.includes(shg: [ :state, :district, :block, :village, :created_by ])
    members = members.where(created_at: params[:date_from].to_date.beginning_of_day..) if params[:date_from].present?
    members = members.where(created_at: ..params[:date_to].to_date.end_of_day) if params[:date_to].present?
    members = members.where(shg_id: params[:shg_id]) if params[:shg_id].present?
    if can_filter_member_state_district_crp?
      members = members.joins(:shg).where(shgs: { state_id: params[:state_id] }) if params[:state_id].present?
      members = members.joins(:shg).where(shgs: { district_id: params[:district_id] }) if params[:district_id].present?
      members = members.joins(:shg).where(shgs: { created_by_id: params[:crp_id] }) if params[:crp_id].present?
    end
    members = members.joins(:shg).where(shgs: { block_id: params[:block_id] }) if params[:block_id].present?
    members = members.joins(:shg).where(shgs: { village_id: params[:village_id] }) if params[:village_id].present?
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
    User.where(id: crp_ids).includes(:user_type).order(:name)
  end

  def can_filter_member_state_district_crp?
    current_user&.admin? || current_user&.assistant_admin?
  end

  def search_members(members)
    query = params[:q].to_s.strip
    return members if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    members.left_joins(shg: [ :state, :district, :block, :village ])
      .where(
        [
          "CAST(shg_members.id AS TEXT) ILIKE :query",
          "LOWER(shg_members.name) LIKE :query",
          "LOWER(COALESCE(shg_members.loan_no, '')) LIKE :query",
          "LOWER(COALESCE(shg_members.mobile, '')) LIKE :query",
          "LOWER(shgs.name) LIKE :query",
          "LOWER(states.name) LIKE :query",
          "LOWER(districts.name) LIKE :query",
          "LOWER(blocks.name) LIKE :query",
          "LOWER(villages.name) LIKE :query"
        ].join(" OR "),
        query: pattern
      ).distinct
  end

  def members_csv(members)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Member", "SHG", "Loan No", "Mobile", "Monthly HH Income",
        "State", "District", "Block", "Village", "Created At"
      ]

      members.each do |member|
        csv << [
          member.name,
          member.shg.name,
          member.loan_no,
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
    params.require(:shg_member).permit(:shg_id, :name, :gender, :dob, :mobile, :loan_no, :monthly_income, :address, :active)
  end
end
