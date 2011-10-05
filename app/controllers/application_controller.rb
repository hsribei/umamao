# -*- coding: undecided -*-
# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include AuthenticatedSystem
  include Subdomains

  protect_from_forgery

  after_filter :flash_to_session
  before_filter :find_group
  before_filter :check_group_access
  before_filter :set_locale
  before_filter :find_languages
  before_filter :check_agreement_to_tos
  before_filter :ensure_domain
  before_filter :track_user
  layout :set_layout

  DEVELOPMENT_DOMAIN = 'localhost.lan'
  TEST_DOMAIN = '127.0.0.1'

  protected

  def ensure_domain
    return unless AppConfig.ensure_domain

    current_domain = request.env['HTTP_HOST']

    # bypass development and test mode (any port)
    return if current_domain.include?(DEVELOPMENT_DOMAIN) or current_domain.include?(TEST_DOMAIN)

    # redirect anydomain.com:anyport/anypath to example.com/anypath
    # (the app's domain)
    if current_domain != AppConfig.domain
      redirect_to(request.url.sub(current_domain, AppConfig.domain),
                  :status => 301)
    end
  end

  def flash_to_session
    if flash[:error]
      cookies[:flash_error] = flash[:error]
      flash.delete(:error)
    elsif flash[:warn]
      cookies[:flash_warn] = flash[:warn]
      flash.delete(:warn)
    elsif flash[:notice]
      cookies[:flash_notice] = flash[:notice]
      flash.delete(:notice)
    end
  end

  def needs_to_agree_with_tos?
    logged_in? && !current_user.agrees_with_terms_of_service?
  end

  # Redirects user to the ToS page if he hasn't agreed with it yet.
  def check_agreement_to_tos
    if needs_to_agree_with_tos? && !request.xhr?
      redirect_to agreement_path
    end
  end

  def track_event(event, properties = {})
    user_id = current_user ? current_user.id : properties.delete(:user_id)
    unless (user = User.find_by_id(user_id)) && user.admin?
      Tracking::EventTracker.delay.track_event([event,
                                                user_id,
                                                request.ip,
                                                properties])
      Tracking::EventTracker.delay.track_event([:any_action,
                                                user_id,
                                                request.ip,
                                                properties])
    end
  end

  def after_sign_in_path_for(resource)
    track_event(:sign_in)
    if resource.is_a?(User) && !resource.has_been_through_wizard?
      # We need to redirect the user to our signup wizard
      wizard_path("connect")
    else
      super
    end
  end

  def require_no_authentication
    redirect_to after_sign_in_path_for(current_user) if current_user
  end

  def check_group_access
    if (
        !current_group.registered_only && !current_group.private ||
        devise_controller? ||
        (params[:controller] == "users" && (action_name == "new" || action_name == 'create') ) ||
        params[:controller] == "welcome" ||
        params[:controller] == "waiting_users" ||
        params[:controller].nil? # it's nil when there's an error
      )
      return
    end

    if logged_in?
      if !current_user.user_of?(@current_group)
        raise Goalie::Forbidden
      end
    else
      session["user_return_to"] = request.url

      respond_to do |format|
        format.json { render :json => {:message => "Permission denied" }}
        format.html { redirect_to new_user_session_path }
      end
    end
  end

  def find_group
    @current_group ||= Rails.cache.fetch('group_first') {
      subdomains = request.subdomains
      subdomains.delete("www") if request.host == "www.#{AppConfig.domain}"
      _current_group = Group.first(:state => "active", :domain => request.host)
      unless _current_group
        _current_group = Group.first(:state => "active",
                                     :domain => AppConfig.domain)
      end
      unless _current_group
        if subdomain = subdomains.first
          _current_group = Group.first(:state => "active",
                                       :subdomain => subdomain) ||
            Group.first
          unless _current_group.nil?
            redirect_to domain_url(:custom => _current_group.domain)
            return
          end
        end
        flash[:warn] = t("global.group_not_found", :url => request.host)
        redirect_to domain_url(:custom => AppConfig.domain)
        return
      end
      _current_group
    }
  end

  def track_user
    if current_user
      handle_event_tracking = lambda do |event, key|
        Rails.cache.write(key, Date.today.to_s)
        track_event(:used_today)
      end
      key = "last_day_used_at_#{current_user.id}"
      if last_day_used_at = Rails.cache.read(key)
        if last_day_used_at != Date.today.to_s
          handle_event_tracking.call(:used_today, key)
        end
      else
        handle_event_tracking.call(:used_today, key)
      end
    end
  end

  def current_group
    @current_group
  end
  helper_method :current_group

  def current_languages
    @current_languages ||= find_languages.join("+")
  end
  helper_method :current_languages

  def find_languages
    @languages ||= begin
      if AppConfig.enable_i18n
        if languages = current_group.language
          languages = [languages]
        else
          if logged_in?
            languages = current_user.languages_to_filter
          elsif session["user.language_filter"]
            if session["user.language_filter"] == 'any'
              languages = AVAILABLE_LANGUAGES
            else
              languages = [session["user.language_filter"]]
            end
          elsif params[:mylangs]
            languages = params[:mylangs].split(' ')
          elsif params[:feed_token] && (feed_user = User.find_by_feed_token(params[:feed_token]))
            languages = feed_user.languages_to_filter
          else
            languages = [I18n.locale.to_s.split("-").first]
          end
        end
        languages
      else
        [current_group.language || AppConfig.default_language]
      end
    end
  end
  helper_method :find_languages

  def language_conditions
    conditions = {}
    conditions[:language] = { :$in => find_languages}
    conditions
  end
  helper_method :language_conditions

  def scoped_conditions(conditions = {})
    conditions.deep_merge!({:group_id => current_group.id})
    conditions.deep_merge!(language_conditions)
  end
  helper_method :scoped_conditions

  def available_locales; AVAILABLE_LOCALES; end

  def set_locale
    locale = AppConfig.default_language || 'en'
    if AppConfig.enable_i18n
      if logged_in?
        locale = current_user.language
        Time.zone = current_user.timezone || "UTC"
      elsif params[:feed_token] && (feed_user = User.find_by_feed_token(params[:feed_token]))
        locale = feed_user.language
      elsif params[:lang] =~ /^(\w\w)/
        locale = find_valid_locale($1)
      elsif request.env['HTTP_ACCEPT_LANGUAGE'] =~ /^(\w\w)/
        locale = find_valid_locale($1)
      end
    end
    I18n.locale = locale.to_s
  end

  def find_valid_locale(lang)
    case lang
      when /^es/
        'es-419'
      when /^pt/
        'pt-BR'
      when "fr"
        'fr'
      when "ja"
        'ja'
      when /^el/
        'el'
      else
        'en'
    end
  end
  helper_method :find_valid_locale

  def set_layout
    devise_controller? || (action_name == "new" && controller_name == "users") ? 'sessions' : 'application'
  end

  def set_page_title(title)
    @page_title = title
  end

  def page_title
    if @page_title
      if current_group.name == AppConfig.application_name
        "#{@page_title} - #{AppConfig.application_name}: #{t("layouts.application.title")}"
      else
        if current_group.isolate
          "#{@page_title} - #{current_group.name} #{current_group.legend}"
        else
          "#{@page_title} - #{current_group.name} - #{AppConfig.application_name} -  #{current_group.legend}"
        end
      end
    else
      if current_group.name == AppConfig.application_name
        "#{AppConfig.application_name} - #{t("layouts.application.title")}"
      else
        if current_group.isolate
          "#{current_group.name} - #{current_group.legend}"
        else
          "#{current_group.name} - #{current_group.legend} - #{AppConfig.application_name}"
        end
      end
    end
  end
  helper_method :page_title

  def feed_urls
    @feed_urls ||= Set.new
  end
  helper_method :feed_urls

  def add_feeds_url(url, title="atom")
    feed_urls << [title, url]
  end

  def admin_required
    unless current_user.admin?
      raise Goalie::Forbidden
    end
  end

  def moderator_required
    unless current_user.mod_of?(current_group)
      raise Goalie::Forbidden
    end
  end

  def owner_required
    unless current_user.owner_of?(current_group)
      raise Goalie::Forbidden
    end
  end

  def is_bot?
    request.user_agent =~ /\b(Baidu|Gigabot|Googlebot|libwww-perl|lwp-trivial|msnbot|SiteUptime|Slurp|WordPress|ZIBB|ZyBorg|Java|Yandex|Linguee|LWP::Simple|Exabot|ia_archiver|Purebot|Twiceler|StatusNet|Baiduspider)\b/i
  end

  def build_date(params, name)
    Time.zone.parse("#{params["#{name}(1i)"]}-#{params["#{name}(2i)"]}-#{params["#{name}(3i)"]}") rescue nil
  end

  def build_datetime(params, name)
    Time.zone.parse("#{params["#{name}(1i)"]}-#{params["#{name}(2i)"]}-#{params["#{name}(3i)"]} #{params["#{name}(4i)"]}:#{params["#{name}(5i)"]}") rescue nil
  end
end
