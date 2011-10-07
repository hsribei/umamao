# -*- coding: utf-8 -*-
class QuestionsController < ApplicationController
  before_filter :login_required, :except => [:index, :show, :tags, :unanswered, :related_questions]
  before_filter :admin_required, :only => [:move, :move_to]
  before_filter :moderator_required, :only => [:close]
  before_filter :check_permissions, :only => [:destroy]
  before_filter :check_update_permissions, :only => [:edit, :update, :revert]
  before_filter :check_favorite_permissions, :only => [:favorite, :unfavorite] #TODO remove this
  before_filter :set_active_tag
  before_filter :check_age, :only => [:show]
  before_filter :check_retag_permissions, :only => [:retag, :retag_to]

  tabs :default => :questions, :tags => :tags,
       :unanswered => :unanswered, :new => :ask_question

  subtabs :index => [[:newest, "created_at desc"], [:hot, "hotness desc, views_count desc"], [:votes, "votes_average desc"], [:activity, "activity_at desc"]],
          :unanswered => [[:newest, "created_at desc"], [:votes, "votes_average desc"]],
          :show => [[:votes, "votes_average desc"], [:oldest, "created_at asc"], [:newest, "created_at desc"]]

  # GET /questions
  # GET /questions.xml
  def index
    set_page_title(t("questions.index.title"))
    conditions = scoped_conditions(:banned => false)

    if params[:sort] == "hot"
      conditions[:activity_at] = {"$gt" => 5.days.ago}
    end

    @questions = Question.paginate({:per_page => 25, :page => params[:page] || 1,
                                   :order => current_order,
                                   :fields => (Question.keys.keys - ["_keywords", "watchers"])}.
                                               merge(conditions))

    @questions_count = Question.count
    @unanswered_questions_count = calculate_unanswered_count

    @langs_conds = scoped_conditions[:language][:$in]

    if logged_in?
      feed_params = { :feed_token => current_user.feed_token }
    else
      feed_params = {  :lang => I18n.locale,
                          :mylangs => current_languages }
    end
    add_feeds_url(url_for({:format => "atom"}.merge(feed_params)), t("feeds.questions"))
    if params[:tags]
      add_feeds_url(url_for({:format => "atom", :tags => params[:tags]}.merge(feed_params)),
                    "#{t("feeds.tag")} #{params[:tags].inspect}")
    end

    set_tab :all, :questions_index

    respond_to do |format|
      format.html # index.html.erb
      format.json  { render :json => @questions.to_json(:except => %w[_keywords slug watchers]) }
      format.atom
    end
  end


  def history
    @question = current_group.questions.find_by_slug_or_id(params[:id])

    respond_to do |format|
      format.html
      format.json { render :json => @question.versions.to_json }
    end
  end

  def diff
    @question = current_group.questions.find_by_slug_or_id(params[:id])
    @prev = params[:prev]
    @curr = params[:curr]
    if @prev.blank? || @curr.blank? || @prev == @curr
      flash[:error] = "please, select two versions"
      render :history
    else
      if @prev
        @prev = (@prev == "current" ? :current : @prev.to_i)
      end

      if @curr
        @curr = (@curr == "current" ? :current : @curr.to_i)
      end
    end
  end

  def revert
    @question.load_version(params[:version].to_i)

    respond_to do |format|
      format.html
    end
  end

  def related_questions
    if params[:id]
      @question = Question.find(params[:id])
    elsif params[:question]
      topics = Topic.from_titles!(params[:question].try(:delete, :topics))
      @question = Question.new(params[:question])
      @question.topics = topics
      @question.group_id = current_group.id
    end

    @question.tags += @question.title.downcase.split(",").join(" ").split(" ")

    @questions = Question.related_questions(@question, :page => params[:page],
                                                       :per_page => params[:per_page],
                                                       :order => "answers_count desc")

    respond_to do |format|
      format.js do
        render :json => {:html => render_to_string(:partial => "questions/question",
                                                   :collection  => @questions,
                                                   :locals => {:mini => true, :lite => true})}.to_json
      end
    end
  end

  def unanswered
    set_page_title(t("questions.unanswered.title"))
    conditions = scoped_conditions(:is_open => true)

    @questions = Question.paginate({:order => current_order,
                                    :per_page => 25,
                                    :page => params[:page] || 1,
                                    :fields => (Question.keys.keys - ["_keywords", "watchers"])
                                   }.merge(conditions))

    @questions_count = Question.count
    @unanswered_questions_count = calculate_unanswered_count

    set_tab :unanswered, :questions_index

    respond_to do |format|
      format.html { render 'index' } # unanswered.html.erb
      format.json  { render :json => @questions.to_json(:except => %w[_keywords slug watchers]) }
    end
  end

  # GET /questions/1
  # GET /questions/1.xml
  def show
    if params[:language]
      params.delete(:language)
      head :moved_permanently, :location => url_for(params)
      return
    end

    if params[:group_invitation]
      session[:group_invitation] = params[:group_invitation]
    end

    @open_sharing_widget = flash[:connected_to]

    options = {:per_page => 25, :page => params[:page] || 1,
               :order => [:votes, "votes_average desc"]}
    @search_results = @question.search_results.paginate(options)

    @answer = Answer.new(params[:answer])
    @search_result = SearchResult.new(params[:search_result])

    if @question.user != current_user && !is_bot?
      @question.viewed!(request.remote_ip)
    end

    set_page_title(@question.title)
    add_feeds_url(url_for(:format => "atom"), t("feeds.question"))

    @follow_up_question = {
      :parent_question_id => @question.id,
      :body => render_to_string(:file => 'questions/_new_follow_up_question.text.erb')
    }
    @follow_up_questions = Question.children_of(@question)

    respond_to do |format|
      format.html
      format.json  { render :json => @question.to_json(:except => %w[_keywords slug watchers]) }
      format.atom
    end
  end

  # GET /questions/new
  # GET /questions/new.xml
  def new
    @question = Question.new(params[:question])
    if @question.parent_question_id.present?
      @question.topics = Question.find_by_id(@question.parent_question_id).topics
    end

    respond_to do |format|
      format.html # new.html.erb
      format.json  { render :json => @question.to_json }
    end
  end

  # GET /questions/1/edit
  def edit
  end

  # POST /questions
  # POST /questions.xml
  def create
    @question = Question.new
    @question.safe_update(%w[title body content_image_ids language wiki
                             parent_question_id], params[:question])
    @question.group = current_group
    @question.user = current_user
    @question.topics = Topic.from_titles!(params[:question][:topics])

    if params[:question][:question_list].present?
      @question_list = QuestionList.find_by_id(params[:question][:question_list])
      @question.topics = @question_list.topics
      @question.topics << @question_list
    end

    if !logged_in?
      draft = Draft.create!(:question => @question)
      session[:draft] = draft.id
      return login_required
    end

    respond_to do |format|
      if @question.save
        current_user.on_activity(:ask_question, current_group)
        current_group.on_activity(:ask_question)

        track_event(:asked_question, :body_present => @question.body.present?,
                    :topics_count => @question.topics.size)

        format.html do
          flash[:notice] = t(:flash_notice, :scope => "questions.create")
          redirect_to(question_path(@question))
        end
        format.js do
          render :json => {
            :success => true,
            :html => render_to_string(:partial => "question_lists/question",
                                      :object => @question)
          }.to_json
        end
        format.json { render :json => @question.to_json(:except => %w[_keywords watchers]), :status => :created}
      else
        format.html { render :action => "new" }
        format.js { render :json => { :success => false, :message => t('questions.create.error') }.to_json }
        format.json { render :json => @question.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /questions/1
  # PUT /questions/1.xml
  def update
    respond_to do |format|
      @question.safe_update(%w[title body language wiki content_image_ids
                               adult_content version_message], params[:question])
      @question.updated_by = current_user
      @question.last_target = @question
      if params[:question][:topics]
        @question.topic_ids_will_change!
        @question.topics = Topic.from_titles!(params[:question][:topics])
      end

      @question.slugs << @question.slug
      @question.send(:generate_slug)

      if @question.valid? && @question.save
        format.html do
          flash[:notice] = t(:flash_notice, :scope => "questions.update")
          redirect_to(question_path(@question))
        end
        format.json  { head :ok }
      else
        format.html { render :action => "edit" }
        format.json  { render :json => @question.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /questions/1
  # DELETE /questions/1.xml
  def destroy
    if @question.user_id == current_user.id
      @question.user.update_reputation(:delete_question, current_group)
    end
    @question.destroy

    respond_to do |format|
      format.html { redirect_to(questions_url) }
      format.json  { head :ok }
    end
  end

  def close
    @question = Question.find_by_slug_or_id(params[:id])

    @question.closed = true
    @question.closed_at = Time.zone.now

    respond_to do |format|
      if @question.save

        format.html { redirect_to question_path(@question) }
        format.json { head :ok }
      else

        format.html do
          flash[:error] = @question.errors.full_messages.join(", ")
          redirect_to question_path(@question)
        end
        format.json { render :json => @question.errors, :status => :unprocessable_entity  }
      end
    end
  end

  def flag
    @question = Question.find_by_slug_or_id(params[:id])
    @flag = Flag.new
    @flag.flaggeable_type = @question.class.name
    @flag.flaggeable_id = @question.id
    respond_to do |format|
      format.html
      format.js do
        render :json => {:status => :ok,
         :html => render_to_string(:partial => "flags/form",
                                   :locals => {:flag => @flag,
                                               :type => :question,
                                               :source => params[:source],
                                               :form_id => "question_flag_form" })
        }
     end
    end
  end

  def favorite
    @favorite = Favorite.new
    @favorite.question = @question
    @favorite.user = current_user
    @favorite.group = @question.group

    @question.add_watcher(current_user)

    if (@question.user_id != current_user.id) && current_user.notification_opts.activities
      Notifier.delay.favorited(current_user, @question.group, @question)
    end

    respond_to do |format|
      if @favorite.save
        @question.add_favorite!(@favorite, current_user)
        notice = t("favorites.create.success")
        format.html do
          flash[:notice] = notice
          redirect_to(question_path(@question))
        end
        format.json { head :ok }
        format.js {
          render(:json => {:success => true,
                   :message => notice, :increment => 1 }.to_json)
        }
      else
        error = @favorite.errors.full_messages.join("**")
        format.html do
          flash[:error] = error
          redirect_to(question_path(@question))
        end
        format.js {
          render(:json => {:success => false,
                   :message => error, :increment => 0 }.to_json)
        }
        format.json { render :json => @favorite.errors, :status => :unprocessable_entity }
      end
    end
  end

  def unfavorite
    @favorite = current_user.favorite(@question)
    if @favorite
      if current_user.can_modify?(@favorite)
        @question.remove_favorite!(@favorite, current_user)
        @favorite.destroy
        @question.remove_watcher(current_user)
      end
    end
    notice = t("unfavorites.create.success")
    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to(question_path(@question))
      end
      format.js do
        render(:json => {
                 :success => true,
                 :message => notice,
                 :increment => -1
               }.to_json)
      end
      format.json  { head :ok }
    end
  end

  def watch
    @question = Question.find_by_slug_or_id(params[:id])
    @question.add_watcher(current_user)
    notice = t("questions.watch.success")
    track_event(:followed_question)

    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to question_path(@question)
      end
      format.js do
        followers_count = @question.watchers.count + 1
        render(:json => {
                 :success => true,
                 :message => notice,
                 :follower => (render_cell :users, :small_picture,
                               :user => current_user),
                 :followers_count =>
                 I18n.t("followable.followers.question.link",
                        :count => followers_count,
                        :link => followers_question_path(@question))
               }.to_json)
      end
      format.json { head :ok }
    end
  end

  def unwatch
    @question = Question.find_by_slug_or_id(params[:id])
    @question.remove_watcher(current_user)
    notice = t("questions.unwatch.success")
    track_event(:unfollowed_question)

    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to question_path(@question)
      end
      format.js do
        followers_count = @question.watchers.count - 1
        render(:json => {
                 :success => true,
                 :message => notice,
                 :user_id => current_user.id,
                 :followers_count =>
                 I18n.t("followable.followers.question.link",
                        :count => followers_count,
                        :link => followers_question_path(@question))
               }.to_json)
      end
      format.json { head :ok }
    end
  end

  # Classifies the question under a certain topic.
  def classify
    @question = Question.find_by_slug_or_id(params[:id])

    @topic = Topic.find_by_title(params[:topic])

    # Create new topic when it doesn't exist yet.
    if @topic.nil?
      @topic = Topic.create(:title => params[:topic])
      @topic.save
    end

    @question.updated_by = current_user
    status = @question.classify! @topic

    respond_to do |format|
      format.html do
        redirect_to question_path(@question)
      end

      format.js do
        res = { :success => status }
        res[:box] = render_to_string(
          :partial => 'topics/topic_box',
          :locals => {
            :topic => @topic,
            :options => {
              :classifiable => @question,
              :ajax_add => true,
              :logged_in => true
            }
          }
        ) if status
        render :json => res.to_json
      end
    end
  end

  # Removes a question from a certain topic.
  def unclassify
    @question = Question.find_by_slug_or_id(params[:id])

    @topic = Topic.find_by_title(params[:topic])
    @question.updated_by = current_user
    status = @question.unclassify! @topic

    respond_to do |format|
      format.html do
        redirect_to question_path(@question)
      end

      format.js do
        render :json => { :success => status }.to_json
      end
    end
  end

  def retag_to
    @question = Question.find_by_slug_or_id(params[:id])

    @question.topics = Topic.from_titles!(params[:question].try(:delete, :topics))

    @question.updated_by = current_user
    @question.last_target = @question

    if @question.save
      if (Time.now - @question.created_at) < 8.days
        @question.on_activity(true)
      end

      notice = t("questions.retag_to.success", :group => @question.group.name)
      respond_to do |format|
        format.html do
          flash[:notice] = notice
          redirect_to question_path(@question)
        end
        format.js do
          topics = @question.topics.map{ |t|
            { :title => CGI.escapeHTML(t.title),
              :url => url_for(t) }
          }
          render(:json => {:success => true,
                   :message => notice, :topics => topics}.to_json)
        end
      end
    else
      error = t("questions.retag_to.failure",
                :group => params[:question][:group])

      respond_to do |format|
        format.html do
          flash[:error] = error
          render :retag
        end
        format.js do
          render(:json => {
                   :success => false,
                   :message => error
                 }.to_json)
        end
      end
    end
  end


  def retag
    @question = Question.find_by_slug_or_id(params[:id])
    respond_to do |format|
      format.js {
        render(:json => {
                 :success => true,
                 :html => render_to_string(:partial => "questions/retag_form",
                                           :member  => @question)
               }.to_json)
      }
    end
  end

  def followers
    @question = Question.find_by_slug_or_id(params[:id])
    @followers =
      @question.followers.paginate :per_page => 15, :page => params[:page]
    respond_to do |format|
      format.html
    end
  end

  protected
  def calculate_unanswered_count
    Question.count :is_open => true
  end

  def check_permissions
    @question = Question.find_by_slug_or_id(params[:id])

    if @question.nil?
      redirect_to questions_path
    elsif !@question.can_be_deleted_by?(current_user)
      flash[:error] = t("global.permission_denied")
      redirect_to question_path(@question)
    end
  end

  def check_update_permissions
    @question = current_group.questions.find_by_slug_or_id(params[:id])
    allow_update = true
  end

  def check_favorite_permissions
    @question = current_group.questions.find_by_slug_or_id(params[:id])
    unless logged_in?
      error = t(:unauthenticated, :scope => "favorites.create")
      respond_to do |format|
        format.html do
          flash[:error] = "#{error}, [#{t("global.please_login")}](#{new_user_session_path})"
          redirect_to question_path(@question)
        end
        format.js do
          error += ", <a href='#{new_user_session_path}'> #{t("global.please_login")} </a>"
          render(:json => {:status => :error, :message => error }.to_json)
        end
        format.json do
          error += ", <a href='#{new_user_session_path}'> #{t("global.please_login")} </a>"
          render(:json => {:status => :error, :message => error }.to_json)
        end
      end
    end
  end


  def check_retag_permissions
    @question = Question.find_by_slug_or_id(params[:id])
    unless logged_in? && (current_user.can_retag_others_questions_on?(current_group) ||  current_user.can_modify?(@question))
      reputation = @question.group.reputation_constrains["retag_others_questions"]
      if !logged_in?
        error = t("questions.show.unauthenticated_retag")
      else
        error = I18n.t("users.messages.errors.reputation_needed",
                       :min_reputation => reputation,
                       :action => I18n.t("users.actions.retag_others_questions"))
      end
      respond_to do |format|
        format.html do
          flash[:error] = error
          redirect_to @question
        end
        format.js do
          render(:json => {
                   :success => false,
                   :message => error
                 }.to_json)
        end
      end
    end
  end

  def set_active_tag
    @active_tag = "tag_#{params[:tags]}" if params[:tags]
    @active_tag
  end

  def check_age
    @question = current_group.questions.find_by_slug_or_id(params[:id])

    if @question.nil?
      @question = current_group.questions.first(:slugs => params[:id], :select => [:_id, :slug])
      if @question.present?
        head :moved_permanently, :location => question_url(@question)
        return
      elsif params[:id] =~ /^(\d+)/ && (@question = current_group.questions.first(:se_id => $1, :select => [:_id, :slug]))
        head :moved_permanently, :location => question_url(@question)
      else
        raise Goalie::NotFound
      end
    end

    return if session[:age_confirmed] || is_bot? || !@question.adult_content

    if !logged_in? || (Date.today.year.to_i - (current_user.birthday || Date.today).year.to_i) < 18
      render :template => "welcome/confirm_age"
    end
  end

end
