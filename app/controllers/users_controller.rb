class UsersController < ApplicationController
  prepend_before_filter :require_no_authentication, :only => [:new, :create]
  before_filter :login_required, :only => [:edit, :update, :wizard,
                                           :follow, :unfollow]
  before_filter :common_show, :only => [:show, :questions, :answers, :search_results]

  tabs :default => :users

  subtabs :index => [[:newest, "created_at desc"],
                     [:oldest, "created_at asc"],
                     [:name, "name asc"]]

  def index
    set_page_title(t("users.index.title"))
    options =  {:per_page => params[:per_page]||24,
               :order => current_order,
               :page => params[:page] || 1}
    options[:login] = /^#{Regexp.escape(params[:q])}/ if params[:q]

    @users = User.paginate(options)

    respond_to do |format|
      format.html
      format.json {
        render :json => @users.to_json(:only => %w[name login membership_list bio website location language])
      }
      format.js {
        html = render_to_string(:partial => "user", :collection  => @users)
        pagination = render_to_string(:partial => "shared/pagination", :object => @users,
                                      :format => "html")
        render :json => {:html => html, :pagination => pagination }
      }
    end
  end

  def resend_confirmation_email
    current_user.resend_confirmation_token

    respond_to do |format|
      format.js {
        render :json => {
          :success => true,
          :message => t('users.annoying.resent_confirmation')
        }
      }
    end
  end

  def new
    if params[:group_invitation]
      case_insensitive_slug = Regexp.new("^#{params[:group_invitation]}$",
                                         Regexp::IGNORECASE)
      @group_invitation = GroupInvitation.first(:slug => case_insensitive_slug)
      unless @group_invitation && @group_invitation.active?
        redirect_to(root_path(:focus => "signup")) && return
      end
    end

    @user = User.new

    # User added by invitation
    if params[:invitation_token]
    @invitation = Invitation.
      find_by_invitation_token(params[:invitation_token])

      if @invitation
        @user.email = @invitation[:recipient_email]
        if (m = @user.email.match(/^[a-z](\d{6})@dac.unicamp.br$/)) &&
           (student = Student.find_by_code(m[1], :university_id => University.
                                           find_by_short_name("Unicamp").id))
          @user.name = student.name
        end
        @user.invitation_token = @invitation.invitation_token
      end

    end

    if @invitation || @group_invitation
      @user.timezone = AppConfig.default_timezone
      @signin_index, @signup_index = [6, 1]
      session['sign_up_allowed'] = true
      session['invitation_id'] = @invitation.try(:id) || @group_invitation.try(:slug)
      session['invitation_type'] = if @invitation
                                 "Invitation"
                               elsif @group_invitation
                                 "GroupInvitation"
                               else
                                 nil
                               end
      render 'welcome/landing', :layout => 'welcome'
    else
      return redirect_to(root_path(:focus => "signup"))
    end
  end

  def create
    @user = User.new
    @user.safe_update(%w[login email name password_confirmation password
                         preferred_languages website language timezone
                         identity_url bio invitation_token
                         affiliation_token], params[:user])

    @user.agrees_with_terms_of_service =
      params[:user][:agrees_with_terms_of_service] == "1"

    if params[:user]["birthday(1i)"]
      @user.birthday = build_date(params[:user], "birthday")
    end

    @user.confirmed_at = Time.now if @group_invitation

    if @user.save
      sign_in @user

      group_invitation = params[:group_invitation]
      url_invitation = params[:ref]
      @user.save_user_invitation(:url_invitation => url_invitation,
                                 :group_invitation => group_invitation)
      handle_signup_track(@user, url_invitation, group_invitation)

      current_group.add_member(@user)
      flash[:conversion] = true

      # Protects against session fixation attacks, causes request forgery
      # protection if visitor resubmits an earlier form using back
      # button. Uncomment if you understand the tradeoffs.
      # reset_session
      if @user.active?
        flash[:notice] = t("welcome", :scope => "users.create")
      else
        flash[:notice] = t("confirm", :scope => "users.create")
      end

      redirect_to wizard_path("connect")
    else
      flash[:error]  = t("users.create.flash_error")
      render :action => 'new', :layout => 'welcome'
    end
  end

  def show
    @tab = "news_updates"
    set_tab @tab, :users_show

    @order_info = {:will_sort => false}

    options = {:entry_type => {:$ne => "Answer"}}

    @page = params[:page] || 1
    @items = @user.news_updates.paginate(options.merge(
      {:author_id => @user.id, :per_page => 10,
       :page => @page, :order => :created_at.desc}))

    respond_to do |format|
      format.html
      format.atom
      format.json {
        render :json => @user.to_json(:only => %w[name login membership_list bio website location language])
      }
    end
  end

  def questions
    @tab = "questions"
    set_tab @tab, :users_show

    sort, order = active_subtab(:sort)
    @order_info = {
      :user => @user,
      :will_sort => true,
      :sort => sort,
      :path_used => :questions_user_path,
      :modes => [:use_views_count]
    }

    @page = params[:page] || 1
    @items = @user.questions.paginate(:page => @page,
                                      :order => order,
                                      :per_page => 10,
                                      :group_id => current_group.id,
                                      :banned => false)
    render :show
  end

  def answers
    @tab = "answers"
    set_tab @tab, :users_show

    sort, order = active_subtab(:sort)
    @order_info = {
      :user => @user,
      :will_sort => true,
      :sort => sort,
      :path_used => :answers_user_path,
      :modes => [:use_votes]
    }

    @page = params[:page] || 1
    @items = @user.answers.paginate(:page => @page,
                                    :order => order,
                                    :group_id => current_group.id,
                                    :per_page => 10,
                                    :banned => false)
    render :show
  end

  def search_results
    @tab = 'search_results'
    set_tab @tab, :users_show

    sort, order = active_subtab(:sort)
    @order_info = {
      :user => @user,
      :will_sort => true,
      :sort => sort,
      :path_used => :search_results_user_path,
      :modes => [:use_votes]
    }

    @page = params[:page] || 1
    @items = @user.external_search_results.paginate(:page => @page,
                                                    :order => order,
                                                    :group_id => current_group.id,
                                                    :per_page => 10)
    render :show
  end

  def change_preferred_tags
    @user = current_user
    if params[:tags]
      if params[:opt] == "add"
        @user.add_preferred_tags(params[:tags], current_group) if params[:tags]
      elsif params[:opt] == "remove"
        @user.remove_preferred_tags(params[:tags], current_group)
      end
    end

    respond_to do |format|
      format.html {redirect_to questions_path}
    end
  end

  def follow
    @user = User.find_by_login_or_id(params[:id])

    raise Goalie::NotFound unless @user

    current_user.follow(@user)
    current_user.populate_news_feed!(@user)
    current_user.save!

    track_event(:followed_user)

    notice = t("followable.flash.follow", :followable => @user.name)

    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to user_path(@user)
      end
      format.js {
        followers_count = @user.followers.count
        response = {
          :success => true,
          :message => notice,
          :follower => (render_cell :users, :small_picture,
                        :user => current_user),
          :followers_count => I18n.t("followable.followers.link",
                                     :count => followers_count,
                                     :link => followers_user_path(@user))
        }
        if params[:suggestion]
          response[:suggestions] =
            render_cell :suggestions, :users, :single_column => params[:single_column]
        end
        render :json => response.to_json
      }
    end
  end

  def unfollow
    @user = User.find_by_login_or_id(params[:id])

    raise Goalie::NotFound unless @user

    current_user.unfollow(@user)
    current_user.save!

    track_event(:unfollowed_user)

    notice = t("followable.flash.unfollow", :followable => @user.name)

    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to user_path(@user)
      end
      format.js {
        followers_count = @user.followers.count
        render(:json => {
                 :success => true,
                 :message => notice,
                 :user_id => current_user.id,
                 :followers_count => I18n.t("followable.followers.link",
                                            :count => followers_count,
                                            :link => followers_user_path(@user))
               }.to_json)
      }
    end
  end

  def set_not_new
    current_user.new_user = false
    current_user.save
    respond_to do |format|
      format.js  { render :json => { :success => true }.to_json }
    end
  end

  def followers
    @user = User.find_by_id(params[:id])

    raise Goalie::NotFound unless @user

    @users = @user.followers.paginate :per_page => 15, :page => params[:page]
    respond_to do |format|
      format.html { render "users" }
    end
  end

  def following
    @user = User.find_by_id(params[:id])

    raise Goalie::NotFound unless @user

    @users = @user.following.paginate :per_page => 15, :page => params[:page]
    respond_to do |format|
      format.html { render "users" }
    end
  end

  def topics
    @user = User.find_by_id(params[:id])

    raise Goalie::NotFound unless @user

    @user_topics = UserTopicInfo.query(:user_id => @user.id,
                                       :followed_at.ne => nil, 
                                       :order => :answers_count.desc).
      paginate(:per_page => 15, :page => params[:page])

    if current_user
      user_suggestions = UserSuggestion.all({
        :entry_type => 'Topic', :rejected_at => nil, :accepted_at => nil,
      }.merge(
        if current_user == @user
          { :user_id => current_user.id }
        else
          { :origin_id => current_user.id, :user_id => params[:id] }
        end
      ))

      @suggested_topics = user_suggestions.map(&:entry).uniq.map do |entry|
        [ entry,
          user_suggestions.select{ |s| s.entry_id == entry.id }.map(&:origin) ]
      end
    end

    respond_to do |format|
      format.html
    end
  end

  def destroy
    if false && current_user.delete # FIXME We need a better way to delete users
      flash[:notice] = t("destroyed", :scope => "devise.registrations")
    else
      flash[:notice] = t("destroy_failed", :scope => "devise.registrations")
    end
    return redirect_to(:root)
  end

  def inline_edition
    unless(!["name", "bio", "description"].include?(params[:name]))

      current_user[params[:name]] = params[:value]
      current_user.save

      error_message = if current_user.errors[params[:name]].present? then
                        current_user.errors[params[:name]][0]
                      else
                        ''
                      end

      errors = current_user.errors

      current_user.reload

      empty_field = current_user[params[:name]].blank?
      value = if empty_field then
        t('users.inline_edition.empty_'+params[:name])
      else
        current_user[params[:name]]
      end

      respond_to do |format|
        format.json {
          render :json => {:value => value,
                           :errors => errors,
                           :error  => error_message,
                           :empty_field => empty_field}.to_json
        }
      end
    end
  end

  protected
  def active_subtab(param)
    key = params.fetch(param, "newest")
    order = "created_at desc"
    case key
      when "votes"
        order = "votes_average desc, created_at desc"
      when "views_count"
        order = "views_count desc, created_at desc"
      when "newest"
        order = "created_at desc"
      when "oldest"
        order = "created_at asc"
    end
    [key, order]
  end

  def common_show
    @user = User.find_by_login_or_id(params[:id])

    raise Goalie::NotFound unless @user

    set_page_title(t("users.show.title", :user => @user.name))

    add_feeds_url(url_for(:format => "atom"), t("feeds.user"))

    @user.viewed_on!(current_group) if @user != current_user && !is_bot?
  end

end
