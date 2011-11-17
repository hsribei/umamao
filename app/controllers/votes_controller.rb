class VotesController < ApplicationController
  before_filter :login_required
  before_filter :check_permissions, :except => [:index]

  def index
    redirect_to(root_path)
  end

  # TODO: refactor
  def create
    track_bingo(:voted)

    vote = Vote.new(:voteable_type => params[:voteable_type],
                    :voteable_id => params[:voteable_id],
                    :user => current_user)
    vote_type = ""
    if params[:vote_up] || params['vote_up.x'] || params['vote_up.y']
      vote_type = "vote_up"
      vote.value = 1
    elsif params[:vote_down] || params['vote_down.x'] || params['vote_down.y']
      vote_type = "vote_down"
      vote.value = -1
    end

    saved = vote.save
    state = vote.creation_status
    voteable_class = vote.voteable.class.name.downcase

    if saved
      @notice = t("votes.create.flash_notice")
      event = state || "#{vote.value == 1 ? "up" : "down"}voted".to_sym
      track_event(event, :voteable => voteable_class)
    elsif state == :deleted
      @notice = t("votes.destroy.flash_notice")
      track_event(:removed_vote, :voteable => voteable_class)
    else
      @error_message = vote.errors.full_messages.join(", ")
    end

    respond_to do |format|
      format.html{redirect_to params[:source]}

      format.js do
        if vote.errors.blank?
          average = vote.voteable.reload.votes_average
          render(:json => {:success => true,
                           :message => @notice,
                           :vote_type => vote_type,
                           :vote_state => state,
                           :average => average}.to_json)
        else
          render(:json => {:success => false, :message => @error_message }.to_json)
        end
      end

      format.json do
        if vote.errors.blank?
          average = vote.voteable.reload.votes_average
          render(:json => {:success => true,
                           :message => @notice,
                           :vote_type => vote_type,
                           :vote_state => state,
                           :average => average}.to_json)
        else
          render(:json => {:success => false, :message => @error_message }.to_json)
        end
      end
    end
  end

  def destroy
    @vote = Vote.find(params[:id])
    voteable = @vote.voteable
    value = @vote.value
    if  @vote && current_user == @vote.user
      @vote.destroy
    end
    respond_to do |format|
      format.html { redirect_to params[:source] }
      format.json  { head :ok }
    end
  end

  protected
  def check_permissions
    unless logged_in?
      respond_to do |format|
        format.html do
          flash[:notice] = "#{t(:unauthenticated, :scope => "votes.create")}, [#{t("global.please_login")}](#{new_user_session_path})"
          redirect_to params[:source]
        end
        format.json do
          @error_message = t("global.please_login")
          render(:json => {:status => :unauthenticate, :success => false, :message => @error_message }.to_json)
        end
        format.js do
          @error_message = t("global.please_login")
          render(:json => {:status => :unauthenticate, :success => false, :message => @error_message }.to_json)
        end
      end
    end
  end
end
