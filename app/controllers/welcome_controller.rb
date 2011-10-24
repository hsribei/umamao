# -*- coding: utf-8 -*-
class WelcomeController < ApplicationController
  before_filter :login_required, :only => [:home, :unanswered, :notifications]
  before_filter :calculate_counts, :only => [:home, :unanswered, :notifications]

  helper :questions
  layout 'application'

  def index
    if logged_in?
      calculate_counts
      home
    else
      landing
    end
  end

  def landing
    session[:user_return_to] = params[:return_to]

    @affiliation = Affiliation.new

    @signin_index, @signup_index =
      if params[:focus] == "signup"
        [3, 1]
      else
        [1, 5]
      end

    render 'landing', :layout => 'welcome'
  end

  def home
    @news_items = filter_news_items

    @questions = Question.latest.limit(10) || [] if @news_items.empty?
    @getting_started = Answer.find_by_id("4d42bebf79de4f262d000e4b")

    set_tab :all, :welcome_home
    render 'home'
  end

  def unanswered
    @news_items = filter_news_items :news_update_entry_type => "Question",
      :open_question => true

    set_page_title(t("welcome.unanswered.title"))

    set_tab :unanswered, :welcome_home
    render 'unanswered'
  end

  def notifications
    @user = current_user
    @notifications = @user.notifications.paginate(:per_page => 20,
                                                  :page => params[:page],
                                                  :order => :created_at.desc)
    set_page_title(t("welcome.notifications.title"))

    set_tab :notifications, :welcome_home
    render

    if @notifications.present? &&
        (@user.last_read_notifications_at.blank? ||
         @notifications.first.created_at > @user.last_read_notifications_at)
      @user.last_read_notifications_at = @notifications.first.created_at
      @user.save!
    end
  end

  def about
    set_page_title(t('.welcome.about.title'))
    @users = AppConfig.about['users']
    render 'about', :layout => 'welcome'
  end

  def feedback
    render 'feedback', :layout => 'welcome'
  end

  def send_feedback
    ok = !params[:result].blank? &&
         (params[:result].to_i == (params[:n1].to_i * params[:n2].to_i))

    if !ok
      flash[:error] = I18n.t("welcome.feedback.captcha_error")
      redirect_to feedback_path(:feedback => params[:feedback])
    else
      Notifier.delay.new_feedback(current_user, params[:feedback][:title],
                                                  params[:feedback][:description],
                                                  params[:feedback][:email],
                                                  request.remote_ip)
      redirect_to root_path
    end
  end

  def change_language_filter
    if logged_in? && params[:language][:filter]
      current_user.update_language_filter(params[:language][:filter])
    elsif params[:language][:filter]
      session["user.language_filter"] =  params[:language][:filter]
    end
    respond_to do |format|
      format.html {redirect_to(params[:source] || questions_path)}
    end
  end

  def confirm_age
    if request.post?
      session[:age_confirmed] = true
    end

    redirect_to params[:source].to_s[0,1]=="/" ? params[:source] : root_path
  end

  protected
  def filter_news_items(options = {})
    NewsItem.paginate({
      :recipient_id => current_user.id, :recipient_type => "User",
      :per_page => 15, :page => params[:page] || 1,
      :order => :created_at.desc, :visible => true}.merge(options))
  end

  def calculate_counts
    @unanswered_count = NewsItem.count(
      :recipient_id => current_user.id, :recipient_type => "User",
      :news_update_entry_type => "Question", :open_question => true,
      :visible => true
    )

    @notifications_unread_count = current_user.unread_notifications.count
  end
end

