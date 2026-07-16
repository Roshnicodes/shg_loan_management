class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_user_admin_permission!, except: :profile
  before_action :set_user, only: %i[show edit update destroy reset_password]
  before_action :require_manage_permission!, except: %i[index show reset_password]
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
      redirect_to users_path, alert: "You cannot delete your own login."
      return
    end

    @user.destroy
    redirect_to users_path, notice: "User deleted successfully."
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
    redirect_to users_path, alert: "This user is linked with records, so it cannot be deleted."
  end

  def bulk_destroy
    ids = Array(params[:ids]).reject { |id| id.to_i == current_user.id }
    result = bulk_destroy_records(User.all, ids)
    redirect_to users_path, notice: "Users deleted: #{result[:deleted]}, skipped: #{result[:skipped]}."
  end

  def reset_password
    return redirect_to(users_path, alert: "Password reset is allowed only for CRP and District Coordinator users.") unless @user.crp? || @user.district_coordinator?

    temporary_password = SecureRandom.alphanumeric(10)
    @user.update!(password: temporary_password, password_confirmation: temporary_password)
    redirect_to users_path, notice: "New temporary password for #{@user.name}: #{temporary_password}"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :login_id, :email, :mobile, :designation, :user_type_id, :state_id, :district_id, :block_id, :village_id, :password, :password_confirmation, :active)
  end
end
