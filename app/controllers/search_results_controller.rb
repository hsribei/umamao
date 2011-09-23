class SearchResultsController < ApplicationController
  before_filter :login_required

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
                                        :locals => { :question =>
                                                       @question }) })
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

  def destroy
    @question = Question.find_by_slug(params[:question_id])
    @search_result = @question.search_results.find(params[:id])
    if @search_result.user_id == current_user.id
      @search_result.user.update_reputation(:delete_search_result, current_group)
    end
    @search_result.destroy
    @question.search_result_removed!

    respond_to do |format|
      format.html { redirect_to(question_path(@question)) }
      format.json { head(:ok) }
    end
  end
end
