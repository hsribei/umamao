class SearchResultsController < ApplicationController
  before_filter :login_required, :except => [:show]
  before_filter :check_permissions, :only => [:destroy]
  before_filter :check_update_permissions, :only => [:edit, :update, :revert]

  helper :votes

  def show
    @open_sharing_widget = flash[:connected_to]

    @search_result = SearchResult.find(params[:id])

    raise Goalie::NotFound unless @search_result

    if params[:group_invitation]
      session[:group_invitation] = params[:group_invitation]
    end

    @question = @search_result.question
    set_page_title(@search_result.title)
    respond_to do |format|
      format.html
      format.json  { render :json => @search_result.to_json }
    end
  end

  def create
    @question = Question.find_by_id(params[:question_id])
    respond_to do |format|
      if (@search_result = SearchResult.new(params[:search_result])).save
        flash[:notice] = t(:flash_notice, :scope => "search_results.create")
        format.html do
          redirect_to(question_path(@question))
        end
        format.js do
          render(:json =>
                   { :success => true,
                     :form_message => flash[:notice],
                     :message => flash[:notice],
                     :html =>
                       render_to_string(:partial => "questions/search_result",
                                        :object => @search_result,
                                        :locals => { :question => @question }) })
        end
        format.json { head(:created) }
      else
        flash[:error] = @search_result.errors.full_messages.join(', ')
        format.html do
          render(@question)
        end
        format.js do
          render(:json => { :success => false, :message => flash[:error] })
        end
        format.json do
          render(:json => { :status => :unprocessable_entity,
                            :message => flash[:error] })
        end
      end
    end
  end

  protected

  def check_permissions
    @search_result = SearchResult.find(params[:id])
    if !@search_result.nil?
      unless (current_user.can_modify?(@search_result) || current_user.mod_of?(@search_result.group))
        flash[:error] = t("global.permission_denied")
        redirect_to question_path(@search_result.question)
      end
    else
      redirect_to questions_path
    end
  end

  def check_update_permissions
    @search_result = SearchResult.find(params[:id])

    raise Goalie::NotFound unless @search_result

    allow_update = true
  end
end
