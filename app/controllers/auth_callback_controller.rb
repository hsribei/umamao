class AuthCallbackController < ApplicationController
  respond_to :html
  before_filter :login_required, :only => :create_external_account

  def callback
    auth_hash = request.env['omniauth.auth']
    if !user_signed_in? && auth_hash['provider'] == 'facebook'
      signup_with_provider
    else
      create_external_account
    end
  end

  def failure
    respond_to do |format|
      format.html { redirect_to session["omniauth_return_url"] }
    end
  end

  def create_external_account
    auth_hash = request.env['omniauth.auth']

    if session["umamao.topic_id"].present? &&
        auth_hash.present? && auth_hash["provider"] == "twitter"
      # Associate this Twitter account with a Topic.
      topic = Topic.find_by_slug_or_id(session.delete("umamao.topic_id"))
      raise Goalie::NotFound if topic.blank?
      TopicExternalAccount.create(auth_hash.merge(:topic => topic))
      redirect_to topic_path(topic)
      return
    end

    if request.env['omniauth.error.type'].present?
      respond_to do |format|
        flash[:error] = I18n.t("external_accounts.connection_error")
        format.html { redirect_to session["omniauth_return_url"] }
      end
      return
    end

    unless @external_account = UserExternalAccount.find_from_hash(auth_hash)
      @external_account =
        UserExternalAccount.create(auth_hash.merge(:user => current_user))
    end

    if @external_account && @external_account.user.id == current_user.id
      respond_with(@external_account, :status => :created) do |format|
        track_event("connected_#{@external_account.provider}".to_sym)
        flash[:connected_to] = @external_account.provider
        format.html { redirect_to session["omniauth_return_url"] }
      end
    else
      flash[:error] = I18n.t("external_accounts.connection_error")
      redirect_to session["omniauth_return_url"]
    end
  end

  def signup_with_provider
    auth_hash = request.env['omniauth.auth']

    user_info = auth_hash["user_info"]
    email = user_info["email"]
    user = User.find_by_email(email)

    if user
      if user.external_accounts.first(:provider => auth_hash['provider'])
        sign_in user
        redirect_to root_path
      else
        session["omniauth-hash"] = auth_hash
        @email = auth_hash["user_info"]["email"]
        @user = User.new
        render :signup_with_provider
      end
    else
      if session['sign_up_allowed']
        if user = User.create_with_provider(auth_hash)
          track_bingo(:signed_up_action)

          sign_in user
          redirect_to wizard_path("follow")
        else
          head(:unprocessable_entity)
        end
      else
        flash[:error] = I18n.t("welcome.landing.invitation_only")
        redirect_to root_path
      end
    end
  end

  def sign_in_and_associate_provider
    auth_hash = session['omniauth-hash']
    user = User.find_by_email(auth_hash["user_info"]["email"])
    if user.valid_password?(params[:user][:password])
      session.delete('omniauth-hash')
      sign_in user
      UserExternalAccount.create(auth_hash.merge(:user => user))
      redirect_to root_url
    else
      flash[:error] = I18n.t('auth_callback.invalid_password')
      @email = auth_hash["user_info"]["email"]
      @user = User.new
      render :signup_with_provider
    end
  end
end
