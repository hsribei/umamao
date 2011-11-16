class SignupWizardController < ApplicationController
  before_filter :login_required

  def wizard
    track_event("wizard_#{params[:current_step]}".to_sym)
    if ["skip", "finish"].include?(params[:current_step])
      current_user.has_been_through_wizard = true
      current_user.save!
      redirect_to root_path
    else
      @current_step = params[:current_step]
      render :layout => "welcome"
    end
  end

  def find
    respond_to do |format|
      format.js do
        render :json => {
          :success => true,
          :html => (render_cell :signup_wizard, :follow)
        }.to_json
      end
    end
  end

end
