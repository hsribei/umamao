require 'uri'

class SearchResult
  REDIRECTION_LIMIT = 4

  include MongoMapper::Document
  include Support::Voteable
  include ApplicationHelper

  key :_id, String
  key :_type, String
  key :url, String
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
                    :if => :url_present?,
                    :unless => :url_has_scheme?

  validate :fetch_url_metadata, :if => :url_present?

  after_validation :fetch_title, :fetch_summary, :if => :response_present?

  validates_presence_of :url
  validates_format_of :url, :with => URI.regexp(%w[http https]), :allow_blank => true

private

  def url_present?
    url.present?
  end

  def response_present?
    @response.present?
  end

  def url_has_scheme?
    !!URI.parse(url).scheme
  rescue URI::InvalidURIError
    false
  end

  def prepend_scheme_on_url
    scheme = lambda { |scheme| scheme ? scheme : 'http' }
    port = lambda { |port| [80, 443, nil].include?(port) ? '' : ":#{port}" }
    uri = URI.parse(url)
    self.url = "#{scheme.call(uri.scheme)}://#{uri.host}#{port.call(uri.port)}#{uri.path}"
  rescue URI::InvalidURIError
    self.url = "http://#{url}"
  end

  def fetch_url_metadata
    fetch = lambda do |uri, redirection_limit|
      raise ArgumentError, 'HTTP redirect too deep' if redirection_limit == 0
      case response = Net::HTTP.get_response(URI.parse(uri))
      when Net::HTTPSuccess then response
      when Net::HTTPRedirection then fetch.call(response['location'],
                                                redirection_limit - 1)
      else response.error!
      end
    end
    @response = fetch.call(url, REDIRECTION_LIMIT)
  rescue URI::InvalidURIError,
         SocketError,
         Errno::ECONNREFUSED,
         Net::HTTPServerException,
         ArgumentError
    errors.add(:url, $!)
  end

  def fetch_title
    title = Nokogiri::HTML(@response.body).xpath('//title').text
    self.title = title.present? ? title : url
  end

  def fetch_summary
    summary = Nokogiri::HTML(@response.body).
                xpath("//meta[translate(@name, '#{('A'..'Z').to_a.to_s}', " <<
                        "'#{('a'..'z').to_a.to_s}')='description']/@content").
                text
    self.summary = if summary.present?
                     summary
                   else
                     html = Nokogiri::HTML(@response.body)
                     html.xpath('//script').remove
                     truncate_words(html.xpath('//body').text, 200)
                   end
  end
end
