# -*- coding: utf-8 -*-
# Methods added to this helper will be available to all templates in the application.

require 'uri'

module ApplicationHelper

  def context_panel_ads(group)
    if AppConfig.enable_adbard && request.domain == AppConfig.domain &&
        !Adbard.find_by_group_id(current_group.id)
      adbard = "<!--Ad Bard advertisement snippet, begin -->
        <script type='text/javascript'>
        var ab_h = '#{AppConfig.adbard_host_id}';
        var ab_s = '#{AppConfig.adbard_site_key}';
        </script>
        <script type='text/javascript' src='http://cdn1.adbard.net/js/ab1.js'></script>
        <!--Ad Bard, end -->"
    else
      adbard = ""
    end
    if group.has_custom_ads == true
      ads = []
      Ad.find_all_by_group_id_and_position(group.id,'context_panel').each do |ad|
        ads << ad.code
      end
      ads << adbard
      return ads.join unless ads.empty?
    end
  end

  def header_ads(group)
    if group.has_custom_ads
      ads = []
      Ad.find_all_by_group_id_and_position(group.id,'header').each do |ad|
        ads << ad.code
      end
      return ads.join  unless ads.empty?
    end
  end

  def content_ads(group)
    if group.has_custom_ads
      ads = []
      Ad.find_all_by_group_id_and_position(group.id,'content').each do |ad|
        ads << ad.code
      end
      return ads.join  unless ads.empty?
    end
  end

  def footer_ads(group)
    if group.has_custom_ads
      ads = []
      Ad.find_all_by_group_id_and_position(group.id,'footer').each do |ad|
        ads << ad.code
      end
      return ads.join  unless ads.empty?
    end
  end

  def language_desc(langs)
    langs.map do |lang|
      I18n.t("languages.#{lang}", :default => lang).capitalize
    end.join(', ')
  end

  def languages_options(languages=nil, current_languages = [])
    languages = AVAILABLE_LANGUAGES-current_languages if languages.blank?
    locales_options(languages)
  end

  def locales_options(languages=nil)
    languages = AVAILABLE_LOCALES if languages.blank?
    languages.collect do |lang|
      [language_desc(lang), lang]
    end
  end

  # Modified Markdown syntax that understands LaTeX math and a couple
  # of other things.
  def markdown(txt, options = {})
    options.reverse_merge!(:process_latex => true, :render_links => true,
                           :keep_newlines => true)
    if options[:process_latex]
      txt = txt.to_s.gsub /\\([\(\[])(.*?)\\([\]\)])/m do |match|
        open  = $1
        math  = $2
        close = $3
        "\\\\" + open + math.gsub(/([_\*\\])/){|m| '\\' + $1} + "\\\\" + close
      end
    end

    if options[:keep_newlines]
      # in very clear cases, let newlines become <br /> tags
      txt.gsub!(/^[ ]{0,3}\S[^\n]*\n+/) do |x|
        x =~ /\n{2}/ ? x : (x.strip!; x << "  \n")
      end
    end

    if options[:render_links]
      txt = render_page_links(txt, options)
      processed_markdown = RDiscount.new(txt, :strict, :autolink).to_html
    else
      processed_markdown = RDiscount.new(txt, :strict).to_html
    end

    if options[:process_latex]
      processed_markdown = Nokogiri::HTML(processed_markdown)
      processed_markdown.css("code").each do |c|
        c.content = c.content.gsub /\\\\([\(\[])(.*?)\\\\([\]\)])/m do |match|
          match.gsub(/\\([_\*\\\[\]\(\)])/, '\1')
        end
      end
      res = processed_markdown.to_html
    else
      res = processed_markdown
    end

    if options[:sanitize] != false
      res = Sanitize.clean(res, SANITIZE_CONFIG)
    end
    res
  end

  def render_page_links(text, options = {})
    group = options[:group] || current_group
    in_controller = respond_to?(:logged_in?)

    text.gsub!(/\[\[([^\,\[\'\"]+)\]\]/) do |m|
      link = $1.split("|", 2)
      page = Page.by_title(link.first, {:group_id => group.id, :select => [:title, :slug]})


      if page.present?
        %@<a href="/pages/#{page.slug}" class="page_link">#{link[1] || page.title}</a>@
      else
        %@<a href="/pages/#{link.first.parameterize.to_s}?create=true&title=#{link.first}" class="missing_page">#{link.last}</a>@
      end
    end

    return text if !in_controller

    text.gsub(/%(\S+)%/) do |m|
      case $1
        when 'site'
          group.domain
        when 'site_name'
          group.name
        when 'current_user'
          if logged_in?
            link_to(current_user.login, user_path(current_user))
          else
            "anonymous"
          end
        when 'hottest_today'
          question = Question.first(:activity_at.gt => Time.zone.now.yesterday, :order => "hotness desc, views_count asc", :group_id => group.id, :select => [:slug, :title])
          if question.present?
            link_to(question.title, question_path(question))
          end
        else
          m
      end
    end
  end

  def format_number(number)
    if number < 1000
      number.to_s
    elsif number >= 1000 && number < 1000000
      "%.01fK" % (number/1000.0)
    elsif number >= 1000000
      "%.01fM" % (number/1000000.0)
    end
  end

  def class_for_number(number)
    if number >= 1000 && number < 10000
      "medium_number"
    elsif number >= 10000
      "big_number"
    elsif number < 0
      "negative_number"
    end
  end

  def shapado_auto_link(text, options = {})
    text = auto_link(text, :all,  { "rel" => 'nofollow', :class => 'auto-link' })
    if options[:link_users]
      text = TwitterRenderer.auto_link_usernames_or_lists(text, :username_url_base => "#{users_path}/", :suppress_lists => true)
    end

    text
  end

  def require_js(*files)
    content_for(:js) { javascript_include_tag(*files) }
  end

  def require_css(*files)
    content_for(:css) { stylesheet_link_tag(*files) }
  end

  def class_for_question(question)
    klass = ""

    if question.accepted
      klass << "accepted"
    elsif !question.answered
      klass << "unanswered"
    end

    if logged_in?
      if current_user.is_preferred_tag?(current_group, *question.tags)
        klass << " highlight"
      end

      if current_user == question.user
        klass << " own_question"
      end
    end

    klass
  end

  def googlean_script(analytics_id, domain)
    "<script type=\"text/javascript\">
       var _gaq = _gaq || [];
       _gaq.push(['_setAccount', '#{analytics_id}']);
       _gaq.push(['_trackPageview'],['_setDomainName', '#{domain}']);

       (function() {
         var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
         ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
         (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(ga);
       })();
    </script>"
  end

  def logged_out_language_filter
    custom_lang = session["user.language_filter"]
    case custom_lang
    when "any"
      languages = "any"
    else
      languages = session["user.language_filter"] || I18n.locale.to_s.split('-').first
    end
    languages
  end

  def clean_seo_keywords(tags, text = "")
    if tags.size < 5

      text.scan(/(\S+)/) do |s|
        word = s.to_s.downcase
        if word.length > 3 && !tags.include?(word)
          tags << word
        end

        break if tags.size >= 5
      end
    end

    tags.join(', ')
  end

  def current_announcements(hide_time = nil)
    conditions = {:starts_at.lte => Time.zone.now.to_i,
                  :ends_at.gte => Time.zone.now.to_i,
                  :order => "starts_at desc",
                  :group_id.in => [current_group.id, nil]}
    if hide_time
      conditions[:updated_at] = {:$gt => hide_time}
    end

    if logged_in?
      conditions[:only_anonymous] = false
    end

    Announcement.all(conditions)
  end

  def top_bar_links
    top_bar = current_group.custom_html.top_bar
    return [] if top_bar.blank?

    top_bar.split("\n").map do |line|
      render_page_links(line.strip)
    end
  end

  def truncate_words(text, length = 140, more_string = '…')
    words = text.to_s.split
    ''.tap { |result|
      chars_left = length

      while chars_left > 0 && words.size > 0 && words.first.size < chars_left
        chars_left -= words.first.size + 1
        result << " #{words.shift}"
      end

      result << more_string unless words.empty?
    }
  end

  def link_to_model(model, text = "")
    if model
      if m = find_link_to_method(model.class)
        m.call(model)
      else
        link_to text, url_for(model)
      end
    end
  end

  def waiting_tag
    image_tag("ajax-loader-big.gif", :alt => t("global.waiting"),
              :class => "waiting")
  end

  def shorten_url(url)
    uri = URI.parse(url)
    port = lambda { |uri| [80, 443].include?(uri.port) ? '' : ":#{uri.port}" }
    relevant_path = lambda do |uri|
      request_uri =
        uri.to_s[((uri.scheme.to_s + uri.host.to_s).to_s.length + 3)..-1].to_s
      head = truncate(request_uri[0..(request_uri.length / 2)], :length => 30)
      tail = truncate(request_uri.reverse[0..(request_uri.length / 2) - 1],
                      :length => 30).reverse
      (head + tail).sub('......', '...')
    end
    "#{uri.scheme}://#{uri.host}#{port.call(uri)}#{relevant_path.call(uri)}"
  rescue URI::InvalidURIError
    truncate(url, :length => 100)
  end

  private

  def find_link_to_method(object_class)
    method_name = "link_to_#{object_class.name.underscore}"
    if respond_to? method_name
      return method(method_name)
    end
    if object_super = object_class.superclass
      find_link_to_method(object_super)
    end
  end
end

