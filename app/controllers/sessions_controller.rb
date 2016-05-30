class SessionsController < ApplicationController
  skip_before_action :ensure_authenticated_user, only: %i( new create )

  def new
    @user = User.new
  end

  def create
    user = User.find_or_create_by!(user_auth_params)
    authenticate_user(user.id)
    redirect_to :root
  end

  def destroy
    unauthenticate_user
    redirect_to new_session_url
  end

  protected

  def user_auth_params
    params.require(:user).permit(:name)
  end
end