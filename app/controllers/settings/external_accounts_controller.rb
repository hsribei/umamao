class Settings::ExternalAccountsController < ApplicationController
  respond_to :html
  before_filter :login_required
  layout 'settings'
  set_tab :external_accounts, :settings

  def index
  end

  def destroy
    @external_account = ExternalAccount.find(params[:id])
    @external_account.destroy
    respond_with(@external_account, :status => :ok) do |format|
      format.html { redirect_to session["omniauth_return_url"] }
    end
  end
end
