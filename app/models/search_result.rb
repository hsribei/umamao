class SearchResult
  TITLE_SIZE        = 100
  SUMMARY_SIZE      = 250

  include MongoMapper::Document
  include Support::Voteable
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  include Support::Xpath

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

  validate :fetch_response_body,
           :if => :url_present?,
           :unless => [:title_present?, :summary_present?]

  after_validation :fill_title,
                   :unless => :title_present?,
                   :if => [:response_body_present?, :response_body_text?]

  after_validation :fill_summary,
                   :unless => :summary_present?,
                   :if => [:response_body_present?, :response_body_text?]

  after_create :notify_watchers, :unless => :has_answer?

  # https://github.com/jnunemaker/mongomapper/issues/207
  before_destroy Proc.new { |sr| sr.answer.destroy if sr.answer }

  validates_presence_of :url
  validates_uniqueness_of(:url, :scope => :question_id)

  def topics
    question.topics
  end

  def on_add_vote(v, voter)
    if v > 0
      self.user.update_reputation(:answer_receives_up_vote, self.group)
      voter.on_activity(:vote_up_answer, self.group)
      self.question.on_answer_votes_balance_up self
    else
      self.user.update_reputation(:answer_receives_down_vote, self.group)
      voter.on_activity(:vote_down_answer, self.group)
      self.question.on_answer_votes_balance_down self
    end

    UserTopicInfo.vote_added!(self, v)
    update_question_answered_with
  end

  def on_remove_vote(v, voter)
    if v > 0
      self.user.update_reputation(:answer_undo_up_vote, self.group)
      voter.on_activity(:undo_vote_up_answer, self.group) if voter
      self.question.on_answer_votes_balance_down self
    else
      self.user.update_reputation(:answer_undo_down_vote, self.group)
      voter.on_activity(:undo_vote_down_answer, self.group) if voter
      self.question.on_answer_votes_balance_up self
    end

    UserTopicInfo.vote_removed!(self, v)
    update_question_answered_with
  end

private
  def update_question_answered_with
    # Update question 'answered' status
    if !self.question.answered && self.votes_average >= 1
      Question.set(self.question.id, {:answered_with_id => self.id})
    elsif self.question.answered_with_id == self.id && self.votes_average < 1
      other_good_answer = self.question.answers.detect { |answer|
        answer.votes_average >= 1
      }

      answered_with_id = other_good_answer ? other_good_answer.id : nil

      Question.set(self.question.id, {:answered_with_id => answered_with_id})
    end
  end

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

  def response_body_present?
    response_body.present?
  end

  def response_body_text?
    @response.content_type.split('/').first == 'text'
  end

  def response_body
    @response ? @response.body : ''
  end

  def fetch_response_body
    @response = Support::ResponseFetcher.new(url, :fetcher => self).fetch
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
                 xpath("//meta[" <<
                         case_insensitive_xpath(:attribute => :name,
                                                :value => :description) <<
                         "]/@content").
                 text,
               :length => SUMMARY_SIZE,
               :omission => ' …',
               :separator => ' ')

    self.summary = if summary.present?
                     summary
                   else
                     html = Nokogiri::HTML(response_body)
                     html.xpath('//script').remove
                     truncate(html.xpath('//p').text,
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
