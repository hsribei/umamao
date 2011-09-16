require 'uri'

class SearchResult
  include MongoMapper::Document
  include Support::Voteable

  key :_id, String
  key :_type, String
  key :url, String, :required => true, :format => URI.regexp(%w[http https])
  key :title, String
  key :summary, String
  key :user_id, String, :index => true
  key :question_id, String, :index => true
  key :group_id, String, :index => true

  timestamps!

  belongs_to :group
  belongs_to :user
  belongs_to :question

  before_validation :prepend_scheme_on_url,
                    :if => Proc.new { |sr| sr.url.present? },
                    :unless => :url_has_scheme?

private

  def url_has_scheme?
    !!URI.parse(url).scheme
  rescue URI::InvalidURIError
    false
  end

  def prepend_scheme_on_url
    scheme = lambda { |scheme| scheme ? scheme : 'http' }
    port = lambda { |port| [80, 443].include?(port) ? '' : ":#{port}" }
    uri = URI.parse(url)
    self.url = "#{scheme.call(uri.scheme)}://#{uri.host}#{port.call(uri.port)}#{uri.path}"
  rescue URI::InvalidURIError
    self.url = "http://#{url}"
  end
end
