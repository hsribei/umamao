class TopicsController < ApplicationController
  before_filter :login_required, :only => [
    :edit, :update, :follow, :unfollow, :ignore, :unignore,
    :toggle_email_subscription
  ]
  respond_to :html

  tabs :default => :topics
  include ShareContentsHelper

  def index
    set_page_title(t("layouts.application.tags"))

    order = params[:sort].try(:to_sym) || :questions_count
    set_tab order, :topics
    order = order.desc if [:questions_count, :created_at].include? order

    @topics = Topic.sort(order).paginate(:per_page => 100,
                                         :page => params[:page] || 1)

    respond_with @topics
  end

  def show
    @topic = Topic.find_by_slug_or_id(params[:id])

    if params[:group_invitation]
      session[:group_invitation] = params[:group_invitation]
    end

    if @topic.nil? && params[:id].include?("%")
      @topic = Topic.find_by_slug(CGI::unescape(params[:id]))    
    end

    raise Goalie::NotFound unless @topic

    if @topic.is_a?(QuestionList)
      redirect_to question_list_path(@topic)
      return
    end

    @open_sharing_widget = flash[:connected_to]

    set_page_title(@topic.title)

    set_tab :all, :topic_show

    if @topic.is_a?(Course) && current_user &&
        current_user.affiliated_with?(@topic.university)
      @students_course = @topic.unregistered_students.query(:limit => 6)
    end

    @question_lists =
      @topic.indirect_question_lists.paginate(:per_page => 6,
                                              :order => :created_at.desc)

    @news_items = NewsItem.paginate(
      :recipient_id => @topic.id,
      :recipient_type => "Topic",
      :per_page => 30,
      :page => params[:page] || 1,
      :order => :created_at.desc,
      :visible => true)

    @questions = Question.paginate(
      :topic_ids => @topic.id, :banned => false,
      :order => :activity_at.desc, :per_page => 25,
      :page => params[:page] || 1) if @news_items.blank?

    respond_with @topics
  end

  def edit
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    respond_with @topic
  end

  def update
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    @topic.safe_update(%w[title description], params[:topic])
    @topic.updated_by = current_user
    @topic.save
    track_event(:edited_topic)

    Question.all(:topic_ids => @topic.id,
                 :select => [:id, :updated_at]).each do |question|
    end

    respond_with @topic
  end

  def follow
    @topic = if params[:id]
               Topic.find_by_slug_or_id(params[:id])
             elsif params[:title]
               Topic.first_or_create(:title => params[:title])
             end

    raise Goalie::NotFound unless @topic

    user = current_user

    # accept user suggestions on that topic
    user_suggestions = UserSuggestion.all(
      :entry_id => @topic.id, :entry_type => 'Topic', :user_id => user.id)

    unless user_suggestions.empty?
      user_suggestions.each(&:accept!)
      track_event(:accepted_user_suggestion)
    end

    followers_count = @topic.followers_count + 1
    @topic.add_follower!(user)
    user.remove_suggestion(@topic)
    user.populate_news_feed!(@topic)
    user.save!

    track_event(:followed_topic)

    notice = t("followable.flash.follow", :followable => @topic.title)

    respond_to do |format|
      format.html do
        redirect_to topic_path(@topic)
      end
      format.js do
        res = {
          :success => true,
          :message => notice,
          :follower => (render_cell :users, :small_picture,
                        :user => current_user),
          :followers_count => "#{
            I18n.t("followable.followers.link", :count => followers_count,
                   :link => followers_topic_path(@topic))} "
        }

        if params[:answer]
          # Used when following from settings page
          res[:html] = render_to_string :partial => 'topics/topic',
            :locals => { :topic => @topic }
        elsif params[:suggestion]
          # We need to redraw the topics suggestions
          res[:suggestions] = render_cell :suggestions, :topics, :single_column => params[:single_column]
        end

        render :json => res.to_json
      end
    end
  end

  def unfollow
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    followers_count = @topic.followers_count - 1
    @topic.remove_follower!(current_user)

    current_user.mark_as_uninteresting(@topic)
    current_user.save!

    track_event(:unfollowed_topic)

    notice = t("followable.flash.unfollow", :followable => @topic.title)

    respond_to do |format|
      format.html do
        redirect_to topic_path(@topic)
      end
      format.js do
        render(:json => {
          :success => true,
          :message => notice,
          :user_id => current_user.id,
          :followers_count => "#{
            I18n.t("followable.followers.link", :count => followers_count,
                   :link => followers_topic_path(@topic.id))} "

        }.to_json)
      end
    end
  end

  def ignore
    @topic =
      if params[:id]
        Topic.find_by_slug_or_id(params[:id])
      elsif params[:title]
        Topic.find_by_title(params[:title])
      end

    raise Goalie::NotFound unless @topic

    current_user.ignore_topic!(@topic)

    track_event(:ignored_topic)

    notice = t("ignorable.flash.ignore", :ignorable => @topic.title)

    respond_to do |format|
      format.html do
        redirect_to topic_path(@topic)
      end

      format.js do
        res = {
          :success => true,
          :message => notice
        }

        if params[:answer]
          # Used when following from settings page
          res[:html] = render_to_string :partial => 'topics/topic',
            :locals => { :topic => @topic, :type => 'ignore' }
        end

        render :json => res.to_json
      end
    end
  end

  def unignore
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    current_user.unignore_topic!(@topic)

    track_event(:unignored_topic)

    notice = t('ignorable.flash.unignore', :ignorable => @topic.title)

    respond_to do |format|
      format.html do
        redirect_to topic_path(@topic)
      end

      format.js do
        render :json => {
          :success => true,
          :message => notice
        }.to_json
      end
    end
  end

  def user_suggest
    @topic = Topic.find_by_id(params[:id]) || Topic.find_by_title(params[:id])
    receiver = User.find_by_id(params[:user])

    if @topic.nil?
      notice = t('user_suggestions.user_suggest.notice.invalid_topic')
      success = false
    else
      begin
        receiver.add_user_suggestion(current_user, @topic)
      rescue MongoMapper::DocumentNotValid => e
        success = false
        notice = t(
          case e.message
          when 'Validation failed: User already have been suggested that topic by origin'
            'user_suggestions.user_suggest.notice.suggestion_exists'
          when 'Validation failed: User already follows entry'
            'user_suggestions.user_suggest.notice.already_follow'
          when 'Validation failed: User and origin are the same'
            'user_suggestions.user_suggest.notice.user_is_origin'
          end, :user => receiver.name, :topic => @topic.title)
      else
        success = true
        notice = t('user_suggestions.user_suggest.notice.ok',
                   :user => receiver.name, :topic => @topic.title)
      end
    end

    track_event(:user_suggested_topic)

    respond_to do |format|
      format.js do
        res = {
          :success => success,
          :message => notice
        }

        if success and params[:answer]
          # Used when suggesting a topic from user's topic page;
          # requires a rendered topic to be shown

          res[:html] =
            case params[:answer]
            when 'topic'
              render_to_string :partial => 'topics/topic',
                :locals => { :topic => @topic, :suggestion => 'friend', :receiver => receiver }
            when 'user'
              render_to_string :partial => 'users/user',
                :locals => { :user => receiver, :suggestion => 'friend' }
            end
        end

        render :json => res.to_json
      end
    end

  end

  def toggle_email_subscription
    if params[:id]
      @topic = Topic.find_by_slug_or_id(params[:id])
    elsif params[:title]
      @topic = Topic.find_by_title(params[:title]) ||
        Topic.new(:title => params[:title])
    end

    user = current_user

    # TODO: ignore when user does not follow topic
    # if @topic.follower_ids.include?(user.id)

    if @topic.email_subscriber_ids.include?(user.id)
      @topic.email_subscriber_ids.delete(user.id)
      @topic.save!
      notice = t("topics.show.email_subscription.notice.unsubscribed", :topic => @topic.title)
      track_event(:email_unsubscribed_topic)
    else
      @topic.email_subscriber_ids << user.id
      @topic.save!
      notice = t("topics.show.email_subscription.notice.subscribed", :topic => @topic.title)
      track_event(:email_subscribed_topic)
    end

    respond_to do |format|
      format.html do
        redirect_to topic_path(@topic)
      end
      format.js do
        res = {
          :success => true,
          :message => notice
        }

        render :json => res.to_json
      end
    end
  end

  def unanswered
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    set_page_title(@topic.title)

    set_tab :unanswered, :topic_show

    conditions = scoped_conditions(:answered_with_id => nil, :banned => false,
                                   :closed => false)

    @questions = Question.paginate({:topic_ids => @topic.id, :banned => false,
                                   :order => :activity_at.desc, :per_page => 25,
                                   :page => params[:page] || 1}.merge(conditions))

    @question_lists =
      @topic.indirect_question_lists.paginate(:per_page => 6,
                                              :order => :created_at.desc)

    respond_with @topics
  end

  # DEPRECATED!
  # Searches matching topics and render them in JSON form for input
  # autocomplete.
  def autocomplete
    result = []
    if q = params[:q]
      result = Topic.filter(q, :per_page => 5)
    end

    re = Regexp.new("^#{Regexp.escape q}$")

    if !result.any? {|t| t.title =~ re}
      result << Topic.new(:title => q, :questions_count => 0)
    end

    respond_to do |format|
      format.js do
        render :json =>
          (result.map do |t|
             res = {
               :id => t.id,
               :title => t.title,
               :count => t.questions_count,
               :html => (render_to_string :partial => "autocomplete.html", :locals => {:topic => t, :question => false})
             }
             if !params[:follow]
               render_to_string(:partial => "topic_box",
                                :locals => {:topic => t})
             end
             res
           end.to_json)
      end
    end
  end

  def followers
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    @user_topic_followers = UserTopicInfo.query(
      :topic_id => @topic.id, :followed_at.ne => nil,
      :order => :votes_balance.desc
    ).paginate(:per_page => 15, :page => params[:page])

    if current_user
      user_suggestions = UserSuggestion.query(
        :entry_id => @topic.id, :entry_type => 'Topic',
        :rejected_at => nil, :accepted_at => nil,
        :$or => [{:origin_id => current_user.id},
                 {:user_id => current_user.id }]
      ).all

      @users_suggested = user_suggestions.map(&:user).uniq

      if @users_suggested.delete(current_user)
        @users_suggested.unshift(current_user)
      end

      @users_suggested.map! do |user|
        [ user,
          user_suggestions.select{ |s| s.user_id == user.id }.map(&:origin)]
      end
    end

    respond_to do |format|
      format.html
    end
  end

  def embedded
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    @group_invitation = GroupInvitation.shared_content(
      @topic, "embedded", default_message_group_invitation(@topic))

    @title = params[:title]

    @questions = Question.paginate(:topic_ids => @topic.id, :banned => false,
                                   :order => @topic.default_question_order,
                                   :per_page => 5,
                                   :page =>  1)

    respond_to do |format|
      format.js do
        info = render_to_string :layout => false
        info.gsub!("\n", "").gsub!("\"", "\\\"")
        render :partial => "javascript_embedded.js", :content_type => 'text/javascript', :locals => {:info => info}
      end
      format.html do
        @style = true
        render :layout => false
      end
    end
  end

  def students
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    @course_offers = CourseOffer.query(:course_id => @topic.id)

    @users = Student.all(:registered_course_ids.in => @course_offers.map(&:id)).map(&:user).select{|u| u}
  end

  def question_lists
    @topic = Topic.find_by_slug_or_id(params[:id])

    raise Goalie::NotFound unless @topic

    @question_lists =
      @topic.indirect_question_lists.paginate(:per_page => 20,
                                              :page => params[:page],
                                              :order => :created_at.desc)
  end

  def user_answers
    @topic = Topic.find_by_slug_or_id(params[:id])
    @user  = User.find_by_id(params[:user_id])

    raise Goalie::NotFound unless @topic

    @answers = Answer.query(:user_id => params[:user_id]).select do |answer|
      answer.topic_ids.include? @topic.id
    end.paginate(:per_page => 10, :page => params[:page] || 1)
  end

  def user_questions
    @topic = Topic.find_by_slug_or_id(params[:id])
    @user  = User.find_by_id(params[:user_id])

    raise Goalie::NotFound unless @topic

    @questions = Question.query(
      :user_id => params[:user_id], :topic_ids => @topic.id
    ).paginate(:per_page => 10, :page => params[:page] || 1)
  end

end
