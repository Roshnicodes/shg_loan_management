class SessionsController < ApplicationController
  def new
    @remembered_login_id = cookies.signed[:remember_login_id]
    redirect_to dashboard_path if logged_in?
  end

  def create
    login_id = params[:login_id].to_s.downcase.strip
    user = User.find_by(login_id: login_id)

    if user&.active? && user.authenticate(params[:password])
      session[:user_id] = user.id
      if params[:keep_login] == "1"
        cookies.permanent.signed[:user_id] = user.id
        cookies.permanent.signed[:remember_login_id] = login_id
      else
        cookies.delete(:user_id)
        cookies.delete(:remember_login_id)
      end
      redirect_to dashboard_path, notice: "Welcome back, #{user.name}."
    else
      @remembered_login_id = login_id
      flash.now[:alert] = "Login ID or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    cookies.delete(:user_id)
    redirect_to login_path, notice: "Signed out successfully."
  end
end
