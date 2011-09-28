class SearchResultsController < ApplicationController
  before_filter :login_required

  def create
    @question = Question.find_by_id(params[:question_id])
    respond_to do |format|
      if (@search_result = SearchResult.new(params[:search_result])).save
        if comment = Comment.create(:body => @search_result.comment,
                                    :user => current_user,
                                    :group => current_group,
                                    :commentable => @search_result)
          current_user.on_activity(:comment_question, current_group)
          track_event(:commented, :commentable => @search_result.class.name)
        end
        notice_message = t(:flash_notice, :scope => "search_results.create")
        format.html do
          flash[:notice] = notice_message
          redirect_to(question_path(@question))
        end
        format.js do
          render(:json =>
                   { :success => true,
                     :form_message => notice_message,
                     :message => notice_message,
                     :html =>
                       render_to_string(:partial => "questions/search_result",
                                        :object => @search_result,
                                        :locals => { :question =>
                                                       @question }) })
        end
        format.json { head(:created) }
      else
        error_message = @search_result.errors.full_messages.join(', ')
        format.html do
          flash[:error] = error_message
          render(@question)
        end
        format.js do
          render(:json => { :success => false, :message => error_message })
        end
        format.json do
          render(:json => { :status => :unprocessable_entity,
                            :message => error_message })
        end
      end
    end
  end

  def destroy
    @question = Question.find_by_slug(params[:question_id])
    @search_result = @question.search_results.find(params[:id])
    if @search_result.user_id == current_user.id
      @search_result.user.update_reputation(:delete_search_result, current_group)
    end
    @search_result.destroy
    @question.search_result_removed!

    respond_to do |format|
      format.html do
        flash[:notice] = t(:flash_notice, :scope => "search_results.destroy")
        redirect_to(question_path(@question))
      end
      format.json { head(:ok) }
    end
  end

  def flag
    @search_result = SearchResult.find(params[:id])

    raise Goalie::NotFound unless @search_result

    @flag = Flag.new
    @flag.flaggeable_type = @search_result.class.name
    @flag.flaggeable_id = @search_result.id
    respond_to do |format|
      format.html
      format.js do
        render(:json =>
                 { :status => :ok,
                   :html =>
                     render_to_string(:partial => '/flags/form',
                                      :locals =>
                                        { :flag => @flag,
                                          :source => params[:source],
                                          :form_id =>
                                            'search_result_flag_form' }) })
      end
    end
  end
end
