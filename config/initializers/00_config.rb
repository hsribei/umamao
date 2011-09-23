require 'ostruct'

require "#{Rails.root}/lib/tracking/mixpanel"

config_file = Rails.root + "config/shapado.yml"

options = YAML.load_file(config_file)
if !options[Rails.env]
  raise "'#{Rails.env}' was not found in #{config_file}"
end

AppConfig = OpenStruct.new(options[Rails.env])

# check config
begin
  sample_file = Rails.root + "config/shapado.yml.sample"
  known_options = YAML.load_file(sample_file)[Rails.env]
  if known_options
    known_options.each do |k, v|
      if AppConfig.send(k).nil?
        $stderr.puts "Warning: missing config option: '#{k}'"
      end
    end
  end
end

REPUTATION_CONSTRAINS = {"vote_up" => 15, "flag" => 15, "post_images" => 15,
"comment" => 50, "delete_own_comments" => 50, "vote_down" => 100,
"create_new_tags" => 100, "post_whithout_limits" => 100, "edit_wiki_post" => 100,
"remove_advertising" => 200, "vote_to_open_own_question" => 250, "vote_to_close_own_question" => 250,
"retag_others_questions" => 500, "delete_comments_on_own_questions" => 750,
"edit_others_posts" => 2000, "view_offensive_counts" => 2000, "vote_to_close_any_question" => 3000,
"vote_to_open_any_question" => 3000, "delete_closed_questions" => 10000, "moderate" => 10000, "retag_others_tags" => 60}

# This is defined for backwards compatibility.
REPUTATION_REWARDS = false

REST_AUTH_SITE_KEY         = AppConfig.rest_auth_key
REST_AUTH_DIGEST_STRETCHES = AppConfig.rest_auth_digest_stretches

SANITIZE_CONFIG = {
  :protocols =>  {
                  "a"=>{"href"=>["ftp", "http", "https", "mailto", :relative]},
                  "img"=>{"src"=>["http", "https", :relative]},
                  "blockquote"=>{"cite"=>["http", "https", :relative]},
                  "q"=>{"cite"=>["http", "https", :relative]}
                 },
  :elements  =>  ["a", "b", "blockquote", "br", "caption", "cite", "code", "col",
                  "colgroup", "dd", "dl", "dt", "em", "h1", "h2", "h3", "h4", "h5",
                  "h6", "i", "img", "li", "ol", "p", "pre", "q", "small", "strike",
                  "strong", "sub", "sup", "table", "tbody", "td", "tfoot", "th",
                  "thead", "tr", "u", "ul", "font", "s", "hr", "div"],
  :attributes => {
                  "div" => ["style"],
                  "colgroup"=>["span", "width"],
                  "col"=>["span", "width"],
                  "ul"=>["type"],
                  "a"=>["href", "title"],
                  "img"=>["align", "alt", "height", "src", "title", "width"],
                  "blockquote"=>["cite"],
                  "td"=>["abbr", "axis", "colspan", "rowspan", "width"],
                  "table"=>["summary", "width"],
                  "q"=>["cite"],
                  "ol"=>["start", "type"],
                  "th"=>["abbr", "axis", "colspan", "rowspan", "scope", "width"]
                 }
}

config = Rails.application.config

config.session_options[:domain] = ".#{AppConfig.domain}"
config.session_options[:key] = AppConfig.session_key
config.session_options[:secret] = AppConfig.session_secret

ActionMailer::Base.default_url_options[:host] = AppConfig.domain

if AppConfig.smtp!= nil and AppConfig.smtp["activate"]
  # Yeah, we have to set both
  ActionMailer::Base.delivery_method = :smtp
  config.action_mailer.delivery_method = :smtp
  options = AppConfig.smtp['settings'].symbolize_keys
  ActionMailer::Base.smtp_settings = options
  config.action_mailer.smtp_settings = options
end

if AppConfig.postmark != nil and AppConfig.postmark['activate']
  # Yeah, we have to set both
  ActionMailer::Base.delivery_method = :postmark
  config.action_mailer.delivery_method = :postmark
  options = {:api_key => AppConfig.postmark['api_key']}
  ActionMailer::Base.postmark_settings = options
  config.action_mailer.postmark_settings = options
end

Tracking::Mixpanel::TOKEN = AppConfig.mixpanel['api_key'] if AppConfig.mixpanel

Rails.application.routes.default_url_options[:host] = AppConfig.domain
