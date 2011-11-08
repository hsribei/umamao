class SearchesController < ApplicationController

  def index
    if params[:q].blank?
      redirect_to root_path
      return
    end

    @in = (params[:in] || []).map(&:to_sym)

    if ab_test(:new_question_as_search) == :new_search_scheme
      @question = Question.new(params[:q] ? { :title => params[:q] } : {})
      @bing_results = Support::Bing.search(@question.title)
    end

    if params[:q].present?
      if ab_test(:new_question_as_search) == :new_search_scheme
        @related_results = Support::Search.query(params[:q],
                                                 :page => 1,
                                                 :in => [:topic, :question])
        @user_results = Support::Search.query(params[:q],
                                              :page => 1,
                                              :in => [:user])
      else
        @results = Support::Search.query(params[:q],
                                         :page => params[:page] || 1,
                                         :in => @in)
      end
    end

    respond_to do |format|
      if ab_test(:new_question_as_search) == :new_search_scheme
        format.html { render :action => 'search_as_new_question.html.haml' }
      else
        format.html
      end
    end
  end

  def autocomplete
    # Searches for entries containing keywords in the search box and
    # returns them in JSON form

    unless params[:q].blank?

      phrase = params[:q]

      query_res = phrase.split.map {|w| Regexp.new "^#{Regexp.escape w}"}

      questions = Question.query(:autocomplete_keywords.in => query_res,
                                 :banned => false,
                                 :select => [:title, :slug, :topic_ids]).limit(10)
      topics = Topic.filter(phrase, :per_page => 10,
                            :select => [:title, :slug, :questions_count])
      users = User.filter(phrase, :per_page => 10,
                          :select => [:name, :id, :email])

      # index calculation to sum 10 results and balance between classes
      total_qs = questions.count
      total_ts = topics.length
      total_us = users.length

      total_qs = [total_qs, 10 - [total_ts + total_us, 6].min].min
      total_ts = [total_ts, 10 - total_qs - [total_us, 7 - total_qs].min].min
      total_us = [total_us, 10 - total_qs - total_ts].min

      # JSON serialization
      render :json => ((questions.limit(total_qs).map do |q|
                          {
                            :url => url_for(q),
                            :html => render_to_string(:partial => "questions/autocomplete.html",
                                                      :locals => {:question => q})
                          }
                        end) +
                       (topics[0...total_ts].map do |t|
                          {
                            :url => url_for(t),
                            :html => render_to_string(:partial => "topics/autocomplete.html",
                                                      :locals => {:topic => t})
                          }
                        end) +
                       (users[0...total_us].map do |u|
                          {
                            :url => url_for(u),
                            :html => render_to_string(:partial => "users/autocomplete.html",
                                                      :locals => {:user => u})
                          }
                        end)).to_json
    end
  end
end
