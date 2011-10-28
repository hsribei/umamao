class VanityController < ApplicationController
  include Vanity::Rails::Dashboard

  before_filter :login_required
  before_filter :only_allow_admins

private

  def only_allow_admins
    unless current_user.admin?
      flash[:error] = t('global.permission_denied')
      redirect_to root_url
    end
  end
end
