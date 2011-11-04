class AuthCallbackController < ApplicationController
  respond_to :html
  before_filter :login_required, :only => :create_external_account

  def callback
    create_external_account
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

    respond_with(@external_account, :status => :created) do |format|
      track_event("connected_#{@external_account.provider}".to_sym)
      flash[:connected_to] = @external_account.provider
      format.html { redirect_to session["omniauth_return_url"] }
    end
  end
end
