require "csv"

class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_user_admin_permission!, except: :profile
  before_action :set_user, only: %i[show edit update destroy reset_password disable]
  before_action :require_manage_permission!, except: %i[index show reset_password export]
  before_action :require_bulk_delete_permission!, only: %i[destroy bulk_destroy]

  def index
    @users = paginate_relation(User.includes(:user_type, :state, :district, :block, :village).order(created_at: :desc))
  end

  def show; end

  def profile
    @user = current_user
    render :show
  end

  def new
    @user = User.new(active: true)
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "User registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      redirect_to users_path, notice: "User updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You cannot disable your own login."
      return
    end

    @user.update!(active: false)
    redirect_to users_path, notice: "User disabled successfully."
  end

  def bulk_destroy
    ids = Array(params[:ids]).reject { |id| id.to_i == current_user.id }
    disabled = User.where(id: ids).update_all(active: false, updated_at: Time.current)
    redirect_to users_path, notice: "Users disabled: #{disabled}."
  end

  def disable
    if @user == current_user
      redirect_to users_path, alert: "You cannot disable your own login."
      return
    end

    @user.update!(active: false)
    redirect_to users_path, notice: "#{@user.name} disabled successfully."
  end

  def bulk_disable
    ids = Array(params[:ids]).reject { |id| id.to_i == current_user.id }.compact_blank
    disabled = User.where(id: ids).update_all(active: false, updated_at: Time.current)
    redirect_to users_path, notice: "Users disabled: #{disabled}."
  end

  def reset_password
    return redirect_to(users_path, alert: "Password reset is allowed only for CRP and District Coordinator users.") unless @user.crp? || @user.district_coordinator?

    temporary_password = SecureRandom.alphanumeric(10)
    @user.update!(password: temporary_password, password_confirmation: temporary_password)
    redirect_to users_path, notice: "New temporary password for #{@user.name}: #{temporary_password}"
  end

  def export
    csv = CSV.generate(headers: true) do |rows|
      rows << [ "ID", "Name", "Login ID", "Email", "Mobile", "Designation", "Role", "State", "Districts", "Blocks", "Villages", "Active", "Password" ]
      User.includes(:user_type, :state, :district, :block, :village).order(:id).find_each do |user|
        rows << [
          user.id,
          user.name,
          user.login_id,
          user.email,
          user.mobile,
          user.designation,
          user.user_type&.name,
          user.office_state_names.join(", "),
          user.office_district_names.join(", "),
          user.office_block_names.join(", "),
          user.office_village_names.join(", "),
          user.active? ? "Yes" : "No",
          "Use Reset Password"
        ]
      end
    end

    send_data csv, filename: "cash360-users-#{Date.current.strftime('%Y%m%d')}.csv", type: "text/csv"
  end

  def new_import; end

  def import
    file = params[:file]
    return redirect_to import_users_path, alert: "Please choose a CSV file." unless file.present?

    imported = 0
    updated = 0

    CSV.foreach(file.path, headers: true).with_index(2) do |row, line_no|
      attrs = user_import_attributes(row)
      next if attrs[:login_id].blank?

      user = User.where(active: true).find_or_initialize_by(login_id: attrs[:login_id])
      password = row["Password"].presence || SecureRandom.alphanumeric(10)
      user.assign_attributes(attrs)
      unless user.persisted?
        user.password = password
        user.password_confirmation = password
      end
      user.save!
      user.previous_changes.key?("id") ? imported += 1 : updated += 1
    rescue ActiveRecord::RecordInvalid => e
      redirect_to import_users_path, alert: "Line #{line_no}: #{e.record.errors.full_messages.to_sentence}"
      return
    end

    redirect_to users_path, notice: "Users import complete. New: #{imported}, updated: #{updated}."
  rescue CSV::MalformedCSVError => e
    redirect_to import_users_path, alert: "CSV file could not be read: #{e.message}"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :login_id, :email, :mobile, :designation, :user_type_id, :state_id, :district_id, :block_id, :village_id, :password, :password_confirmation, :active, mapped_district_ids: [], mapped_block_ids: [], mapped_village_ids: [])
  end

  def user_import_attributes(row)
    user_type = UserType.find_by("LOWER(code) = :role OR LOWER(name) = :role", role: row["Role"].to_s.strip.downcase)
    state = State.find_by("LOWER(name) = ?", row["State"].to_s.strip.downcase) if row["State"].present?
    district_ids = ids_from_names(District, row["Districts"])
    block_ids = ids_from_names(Block, row["Blocks"])
    village_ids = ids_from_names(Village, row["Villages"])

    {
      name: row["Name"].presence || row["User Name"],
      login_id: row["Login ID"].to_s.strip,
      email: row["Email"].to_s.strip,
      mobile: row["Mobile"].to_s.strip,
      designation: row["Designation"].to_s.strip,
      user_type: user_type,
      state: state,
      mapped_district_ids: district_ids,
      mapped_block_ids: block_ids,
      mapped_village_ids: village_ids,
      active: !row["Active"].to_s.casecmp?("no")
    }.compact
  end

  def ids_from_names(model, value)
    names = value.to_s.split(",").map(&:strip).reject(&:blank?)
    return [] if names.blank?

    model.where("LOWER(name) IN (?)", names.map(&:downcase)).pluck(:id)
  end
end
