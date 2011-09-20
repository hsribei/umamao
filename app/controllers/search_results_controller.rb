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
end
