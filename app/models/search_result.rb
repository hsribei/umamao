require 'uri'

class SearchResult
  REDIRECTION_LIMIT = 5
  ACCEPTED_SCHEMES  = %w[http https]
  TIMEOUT           = 10
  TITLE_SIZE        = 100
  SUMMARY_SIZE      = 250

  class TooManyRedirectionsError < StandardError; end

  include MongoMapper::Document
  include Support::Voteable
  include ApplicationHelper
  include ActiveSupport::Inflector
  include ActionView::Helpers::TextHelper
  include ActiveSupport::Multibyte

  key :_id, String
  key :_type, String
  key :url, String
  key :title, String
  key :summary, String
  key :user_id, String, :index => true
  key :question_id, String, :index => true
  key :group_id, String, :index => true
  key :flags_count, Integer, :default => 0

  timestamps!

  # This is ugly but needed since our version of mongomapper doesn't support
  # `accepts_nested_attributes_for`.
  attr_accessor :comment

  belongs_to :group
  belongs_to :user
  belongs_to :question
  has_one :answer, :dependent => :destroy
  has_many :comments,
           :foreign_key => 'commentable_id',
           :dependent => :destroy
  has_many :flags, :as => 'flaggeable', :dependent => :destroy
  has_many :notifications, :as => 'reason', :dependent => :destroy

  before_validation :prepend_scheme_on_url,
                    :if => :url_present?,
                    :unless => :url_has_scheme?

  validate :fetch_response,
           :if => :url_present?,
           :unless => [:title_present?, :summary_present?]

  after_validation :fill_title,
                   :unless => :title_present?,
                   :if => :response_present?

  after_validation :fill_summary,
                   :unless => :summary_present?,
                   :if => :response_present?

  after_create :notify_watchers, :unless => :has_answer?

  # https://github.com/jnunemaker/mongomapper/issues/207
  before_destroy Proc.new { |sr| sr.answer.destroy if sr.answer }

  validates_presence_of :url
  validates_uniqueness_of(:url, :scope => :question_id)

  def topics
    question.topics
  end

private

  def has_answer?
    !!answer
  end

  def url_present?
    url.present?
  end

  def title_present?
    title.present?
  end

  def summary_present?
    summary.present?
  end

  def response_present?
    @response.present?
  end

  def url_has_scheme?
    (parsed_url = URI.parse(url)) &&
      ACCEPTED_SCHEMES.include?(parsed_url.scheme)
  rescue URI::InvalidURIError
    false
  end

  def prepend_scheme_on_url
    scheme = lambda { |scheme| ACCEPTED_SCHEMES.include?(scheme) ? scheme :
                                                                   'http' }
    uri = URI.parse(url)
    self.url = "#{scheme.call(uri.scheme)}://#{uri.to_s}"
  rescue URI::InvalidURIError
  end

  def fetch_response
    request_uri = lambda do |uri|
      if uri.respond_to?(:request_uri)
        uri.request_uri
      else
        uri.query ? uri.path + '?' + uri.query : uri.path
      end
    end
    host = lambda { |uri| uri.host || URI.parse(url).host }
    fetch = lambda do |uri, redirections_left|
      raise TooManyRedirectionsError if redirections_left == 0
      parsed_uri = URI.parse(uri)
      request = Net::HTTP::Get.new(request_uri.call(parsed_uri))
      http = Net::HTTP.new(host.call(parsed_uri), parsed_uri.port)
      http.open_timeout = http.read_timeout = TIMEOUT
      if parsed_uri.port == 443
        http.use_ssl = true
        # http://jamesgolick.com/2011/2/15/verify-none..html
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      case response = http.request(request)
      when Net::HTTPSuccess then response
      when Net::HTTPRedirection then fetch.call(response['location'],
                                                redirections_left - 1)
      else response.error!
      end
    end
    @response = fetch.call(url, REDIRECTION_LIMIT)
  rescue Errno::ECONNREFUSED,
         Errno::ECONNRESET,
         Errno::ETIMEDOUT,
         Net::HTTPServerException,
         Net::HTTPBadResponse,
         Net::HTTPFatalError,
         SocketError,
         Timeout::Error,
         TooManyRedirectionsError,
         URI::InvalidURIError
    errors.add_to_base(I18n.t(underscore($!.class.to_s.delete(':')).to_sym,
                              :scope =>
                                [:activerecord, :errors, :search_result]))
  end

  def response_body
    @response_body ||= begin
                         Unicode.tidy_bytes(@response.body)
                       rescue StandardError
                         Unicode.tidy_bytes(@response.body, true)
                       end
  end

  def fill_title
    title = truncate(Nokogiri::HTML(response_body).xpath('//title').text,
                     :length => TITLE_SIZE,
                     :omission => ' …',
                     :separator => ' ')

    self.title = title.present? ? title : url
  end

  def fill_summary
    summary =
      truncate(Nokogiri::HTML(response_body).
                 xpath("//meta[translate(@name, '#{('A'..'Z').to_a.to_s}', " <<
                         "'#{('a'..'z').to_a.to_s}')='description']/@content").
                 text,
               :length => SUMMARY_SIZE,
               :omission => ' …',
               :separator => ' ')

    self.summary = if summary.present?
                     summary
                   else
                     html = Nokogiri::HTML(response_body)
                     html.xpath('//script').remove
                     truncate(html.xpath('//body').text,
                              :length => SUMMARY_SIZE,
                              :omission => ' …',
                              :separator => ' ')
                   end
  end

  def notify_watchers
    watcher_ids =
       question.topics.inject(Set.new(question.watchers)) do |watcher_ids, topic|
         if topic.is_a?(QuestionList)
           watcher_ids.merge(topic.followers.map(&:id))
         else
           watcher_ids
         end
       end
    watcher_ids.each do |watcher_id|
      if (watcher = User.find_by_id(watcher_id)) != user &&
           watcher.notification_opts.new_search_result
        Notifier.delay.new_search_result(watcher, group, self)
        Notification.create!(:user => watcher,
                             :event_type => 'new_search_result',
                             :origin => user,
                             :reason => self)
      end
    end
  end
  handle_asynchronously :notify_watchers

  def flagged!
    collection.update({ :_id => _id} ,
                      { :$inc => { :flags_count => 1 } },
                      :upsert => true)
  end
end
