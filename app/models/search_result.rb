require 'uri'

class SearchResult
  REDIRECTION_LIMIT = 4
  ACCEPTED_SCHEMES = %w[http https]
  TIMEOUT = 3

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
  validates_format_of :url, :with => URI.regexp(ACCEPTED_SCHEMES), :allow_blank => true

private

  def url_present?
    url.present?
  end

  def response_present?
    @response.present?
  end

  def url_has_scheme?
    (parsed_url = URI.parse(url)) && ACCEPTED_SCHEMES.include?(parsed_url.scheme)
  rescue URI::InvalidURIError
    false
  end

  def prepend_scheme_on_url
    scheme = lambda { |scheme| ACCEPTED_SCHEMES.include?(scheme) ? scheme : 'http' }
    port = lambda { |port| [80, 443, nil].include?(port) ? '' : ":#{port}" }
    uri = URI.parse(url)
    self.url = "#{scheme.call(uri.scheme)}://#{uri.to_s}"
  rescue URI::InvalidURIError
  end

  def fetch_url_metadata
    fetch = lambda do |uri, redirection_limit|
      raise ArgumentError, 'HTTP redirect too deep' if redirection_limit == 0
      parsed_uri = URI.parse(uri)
      request = Net::HTTP::Get.new(parsed_uri.request_uri)
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      http.open_timeout = http.read_timeout = TIMEOUT
      if parsed_uri.port == 443
        http.use_ssl = true
        # http://jamesgolick.com/2011/2/15/verify-none..html
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      case response = http.request(request)
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
         Errno::ECONNRESET,
         Errno::ETIMEDOUT,
         Net::HTTPServerException,
         Net::HTTPBadResponse
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
