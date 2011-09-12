# -*- coding: utf-8 -*-
class Question
  include MongoMapper::Document
  include MongoMapperExt::Filter
  include MongoMapperExt::Slugizer
  include MongoMapperExt::Tags
  include Support::Versionable
  include Support::Voteable
  include Support::Search::Searchable
  include Scopes

  ensure_index :tags
  ensure_index :language

  key :_id, String
  key :title, String, :required => true
  key :body, String
  slug_key :title, :unique => true, :min_length => 8
  key :slugs, Array, :index => true
  key :autocomplete_keywords, Array, :index => true

  key :topic_ids, Array, :index => true
  many :topics, :in => :topic_ids

  key :answers_count, Integer, :default => 0
  key :views_count, Integer, :default => 0
  key :hotness, Integer, :default => 0
  key :flags_count, Integer, :default => 0
  key :favorites_count, Integer, :default => 0

  key :adult_content, Boolean, :default => false
  key :banned, Boolean, :default => false
  key :accepted, Boolean, :default => false
  key :closed, Boolean, :default => false
  key :closed_at, Time

  key :content_image_ids, Array
  has_many :content_images, :in => :content_image_ids

  key :parent_question_id, String, :index => true
  belongs_to :parent_question, :class_name => 'Question'
  scope :children_of, lambda { |question|
    where(:parent_question_id => question.id)
  }

  has_many :child_questions, :class_name => 'Question',
    :foreign_key => 'parent_question_id', :dependent => :nullify

  key :answered_with_id, String
  belongs_to :answered_with, :class_name => "Answer"

  key :wiki, Boolean, :default => false
  key :language, String, :default => 'pt-BR'

  key :activity_at, Time

  key :user_id, String, :index => true
  belongs_to :user

  key :answer_id, String
  belongs_to :answer

  key :search_result_ids, Array
  has_many :search_results, :in => :search_result_ids

  key :group_id, String, :index => true
  belongs_to :group

  key :watchers, Array

  key :updated_by_id, String
  belongs_to :updated_by, :class_name => "User"

  key :close_reason_id, String

  key :last_target_type, String
  key :last_target_id, String
  key :last_target_date, Time

  # is_open is true if answer doesn't have any question with
  # positive vote count
  key :is_open, Boolean, :default => true
  # max_votes and min_votes are respectively the maximum and minimum
  # number of votes of all answers of self
  key :max_votes, Integer, :default => 0
  key :min_votes, Integer, :default => 0

  belongs_to :last_target, :polymorphic => true

  has_many :answers, :dependent => :destroy
  has_many :flags, :as => "flaggeable", :dependent => :destroy
  has_many :comments, :as => "commentable", :order => "created_at asc", :dependent => :destroy
  has_many :close_requests

  # This ought to be has_one, but it wasn't working
  has_many :news_updates, :as => "entry", :dependent => :destroy

  has_many :notifications, :as => "reason", :dependent => :destroy

  validates_presence_of :user_id
  validates_uniqueness_of :slug, :scope => :group_id, :allow_blank => true

  validates_length_of :title, :within => 5..280, :message =>
    lambda {
      if title.length < 5
        I18n.t("questions.model.messages.title_too_short")
      else
        I18n.t("questions.model.messages.title_too_long")
      end
    }

  validates_length_of :body, :minimum => 5, :allow_blank => true,
    :allow_nil => true,
    :message => lambda { I18n.t("questions.model.messages.body_too_short") }

  validates_true_for :tags, :logic => lambda { tags.size <= 9 },
    :message => lambda {
                  if tags.size > 9
                    I18n.t("questions.model.messages.too_many_tags")
                  end
                }

  versionable_keys :title, :body, :topic_ids
  filterable_keys :title, :body
  language :language

  before_save :update_activity_at
  before_save :update_autocomplete_keywords
  before_save :adjust_newlines
  before_create :add_question_author_to_watchers
  after_create :create_news_update, :new_question_notification
  after_create :update_topics_questions_count,
    :increment_user_topic_questions_count, :post_on_twitter

  before_destroy :decrement_user_topic_questions_count

  validates_inclusion_of :language, :within => AVAILABLE_LANGUAGES
  validates_true_for :language, :logic => lambda { |q| q.group.language == q.language },
                                :if => lambda { |q| !q.group.language.nil? }
  validate :disallow_spam
  validate :check_useful

  timestamps!

  # TODO: remove this
  def tags=(t)
    if t.kind_of?(String)
      t = t.downcase.split(",").join(" ").split(" ").uniq
    end

    self[:tags] = t
  end

  def self.related_questions(question, opts = {})
    opts[:per_page] ||= 10
    opts[:page]     ||= 1
    opts[:group_id] = question.group_id
    opts[:banned] = false

    Question.paginate(opts.merge(:topic_ids => question.topic_ids,
                                 :_id => {:$ne => question.id}))
  end

  def viewed!(ip)
    view_count_id = "#{self.id}-#{ip}"
    if ViewsCount.find(view_count_id).nil?
      ViewsCount.create(:_id => view_count_id)
      self.collection.update({:_id => self._id}, {:$inc => {:views_count => 1}},
                                                :upsert => true)
    end
  end

  def answer_added!
    self.collection.update({:_id => self._id}, {:$inc => {:answers_count => 1}},
                                              :upsert => true)
    on_activity
  end

  def answer_removed!
    self.collection.update({:_id => self._id}, {:$inc => {:answers_count => -1}},
                                               :upsert => true)
  end

  def flagged!
    self.collection.update({:_id => self._id}, {:$inc => {:flags_count => 1}},
                                               :upsert => true)
  end

  def on_add_vote(v, voter)
    if v > 0
      self.user.update_reputation(:question_receives_up_vote, self.group)
      voter.on_activity(:vote_up_question, self.group)
    else
      self.user.update_reputation(:question_receives_down_vote, self.group)
      voter.on_activity(:vote_down_question, self.group)
    end
    on_activity(false)
  end

  def on_remove_vote(v, voter)
    if v > 0
      self.user.update_reputation(:question_undo_up_vote, self.group)
      voter.on_activity(:undo_vote_up_question, self.group) if voter
    else
      self.user.update_reputation(:question_undo_down_vote, self.group)
      voter.on_activity(:undo_vote_down_question, self.group) if voter
    end
    on_activity(false)
  end

  # keep max_votes, min_votes and is_open up to date when a user
  # votes up an answer of self
  def on_answer_votes_balance_up(answer)
    all_votes = self.answers.map{ |a| a.votes_average }
    self.min_votes = all_votes.empty? ? 0 : all_votes.min

    if answer.votes_average > self.max_votes
      self.max_votes = answer.votes_average
      if self.max_votes > 0
        self.is_open = false
        if self.news_update
          self.news_update.on_question_status_change false
        end
      end
    end

    self.save
  end
  handle_asynchronously :on_answer_votes_balance_up

  # keep max_votes, min_votes and is_open up to date when a user
  # votes down an answer of self
  def on_answer_votes_balance_down(answer)
    all_votes = self.answers.map{ |a| a.votes_average }
    self.max_votes = all_votes.empty? ? 0 : all_votes.max

    if answer.votes_average < self.min_votes
      self.min_votes = answer.votes_average
      if self.max_votes < 1
        self.is_open = true
        if self.news_update
          self.news_update.on_question_status_change true
        end
      end
    end

    self.save
  end
  handle_asynchronously :on_answer_votes_balance_down

  def add_favorite!(fav, user)
    self.collection.update({:_id => self._id}, {:$inc => {:favorites_count => 1}},
                                                          :upsert => true)
    on_activity(false)
  end


  def remove_favorite!(fav, user)
    self.collection.update({:_id => self._id}, {:$inc => {:favorites_count => -1}},
                                                          :upsert => true)
    on_activity(false)
  end

  def on_activity(bring_to_front = true)
    update_activity_at if bring_to_front
    self.collection.update({:_id => self._id}, {:$inc => {:hotness => 1}},
                                                         :upsert => true)
  end

  def update_activity_at
    now = Time.now
    if new?
      self.activity_at = now
    else
      self.collection.update({:_id => self._id}, {:$set => {:activity_at => now}},
                                                 :upsert => true)
    end
  end

  def ban
    self.collection.update({:_id => self._id}, {:$set => {:banned => true}},
                                               :upsert => true)
    topics.each do |topic|
      topic.increment(:questions_count => -1)
    end
  end

  def self.ban(ids)
    ids = ids.map do |id| id end

    self.collection.update({:_id => {:$in => ids}}, {:$set => {:banned => true}},
                                                     :multi => true,
                                                     :upsert => true)
    query(:id.in => ids, :select => :topic_ids).each do |question|
      question.topics.each do |topic|
        topic.increment(:questions_count => -1)
      end
    end
  end

  def unban
    self.collection.update({:_id => self._id}, {:$set => {:banned => false}},
                                               :upsert => true)
    topics.each do |topic|
      topic.increment(:questions_count => 1)
    end
  end

  def self.unban(ids)
    ids = ids.map do |id| id end

    self.collection.update({:_id => {:$in => ids}}, {:$set => {:banned => false}},
                                                     :multi => true,
                                                     :upsert => true)
    query(:id.in => ids, :select => :topic_ids).each do |question|
      question.topics.each do |topic|
        topic.increment(:questions_count => 1)
      end
    end

  end

  def favorite_for?(user)
    user.favorite(self)
  end


  def add_watcher(user)
    if !watch_for?(user)
      self.collection.update({:_id => self.id},
                             {:$push => {:watchers => user.id}},
                             :upsert => true);
    end
  end

  def remove_watcher(user)
    if watch_for?(user)
      self.collection.update({:_id => self.id},
                             {:$pull => {:watchers => user._id}},
                             :upsert => true)
    end
  end

  def watch_for?(user)
    watchers.include?(user._id)
  end

  def followers
    User.query(:id.in => self.watchers)
  end

  def disable_limits?
    self.user.present? && self.user.can_post_whithout_limits_on?(self.group)
  end

  def check_useful
    unless disable_limits?
      if !self.title.blank? && self.title.gsub(/[^\x00-\x7F]/, "").size < 5
        return
      end

      if !self.title.blank? && (self.title.split.count < 4)
        self.errors.add(:title, I18n.t("questions.model.messages.too_short", :count => 4))
      end

      if !self.body.blank? && (self.body.split.count < 4)
        self.errors.add(:body, I18n.t("questions.model.messages.too_short", :count => 3))
      end
    end
  end

  def disallow_spam
    if new? && !disable_limits?
      last_question = Question.first( :user_id => self.user_id,
                                      :group_id => self.group_id,
                                      :order => "created_at desc")

      valid = (last_question.nil? || (Time.now - last_question.created_at) > 20)
      if !valid
        self.errors.add(:body, "Your question looks like spam. you need to wait 20 senconds before posting another question.")
      end
    end
  end

  def answered
    self.answered_with_id.present?
  end

  def self.update_last_target(question_id, target)
    self.collection.update({:_id => question_id},
                           {:$set => {:last_target_id => target.id,
                                      :last_target_type => target.class.to_s,
                                      :last_target_date => target.updated_at.utc}},
                           :upsert => true)
  end

  def can_be_requested_to_close_by?(user)
    ((self.user_id == user.id) && user.can_vote_to_close_own_question_on?(self.group)) ||
    user.can_vote_to_close_any_question_on?(self.group)
  end

  def can_be_deleted_by?(user)
    user.present? && user.admin?
  end

  def close_reason
    self.close_requests.detect{ |rq| rq.id == close_reason_id }
  end

  # Returns the (only) associated news update.
  # We need this because has_one isn't working.
  def news_update
    news_updates.first
  end

  # Classifies self under topic topic.
  def classify!(topic)
    if !topic_ids.include? topic.id
      self.topic_ids_will_change!
      self.topic_ids << topic.id

      self.needs_to_update_search_index

      self.save!
      self.delay.after_topic_inclusion_updates(topic)
      true
    else
      false
    end
  end

  # Notify users and topic about the inclusion of this question in
  # topic. Increment topic's questions count. Hide question for topic
  # ignorers.
  def after_topic_inclusion_updates(topic)

    # We need this to make sure that answers appear after question.
    stamp = Time.zone.now

    # Question updates
    if news_update
      # Users
      topic.followers.each do |follower|
        if NewsItem.query(:recipient_id => follower.id,
                          :recipient_type => "User",
                          :news_update_id => news_update.id).count == 0
          NewsItem.notify!(news_update, follower, topic, stamp)
        end
      end
      # Topic
      if NewsItem.query(:recipient_id => topic.id,
                        :news_update_id => news_update.id).count == 0
        NewsItem.notify!(news_update, topic, topic, stamp)
      end
    end

    if !banned
      topic.increment_questions_count
      UserTopicInfo.question_classified!(self, topic)
    end


    # Ignorers
    ignorer_ids = topic.ignorer_ids
    self.news_update.news_items.each do |ni|
      if ni.recipient_type == 'User' &&
          ignorer_ids.include?(ni.recipient_id)

        ni.hide! if ni.should_be_hidden?([topic.id])
      end
    end

    # Post to Twitter
    topic.post_on_twitter(self) if topic.external_account.present?
  end


  # Removes self from topic topic.
  def unclassify!(topic)
    if topic_ids.include? topic.id
      self.topic_ids_will_change!
      self.topic_ids.delete topic.id
      self.needs_to_update_search_index

      self.save!
      self.delay.after_topic_removal_updates(topic)
      true
    else
      false
    end
  end

  # Remove topic notifications for users that followed the removed
  # topic, and unhide news items for ignorerers of that topic.
  def after_topic_removal_updates(topic)
    # Remove related news items
    if self.news_update
      NewsItem.query(:origin_id => topic.id,
                     :origin_type => "Topic",
                     :news_update_id => self.news_update.id).each &:delete
    end

    self.answers.each do |answer|
      if answer.news_update
        news_items = NewsItem.query(:origin_id => topic.id,
                                    :origin_type => "Topic",
                                    :news_update_id => answer.news_update.id)
        news_items.each(&:delete)
      end
    end

    if !banned
      topic.increment_questions_count -1
      UserTopicInfo.question_unclassified!(self, topic)
    end

    # Ignorers
    ignorer_ids = topic.ignorer_ids
    self.news_update.news_items.each do |ni|
      if ni.recipient_type == 'User' &&
          ignorer_ids.include?(ni.recipient_id)

        ni.show! unless ni.should_be_hidden?([topic.id])
      end
    end
  end

  def create_news_update
    NewsUpdate.create(:author => self.user, :entry => self,
                      :created_at => self.created_at, :action => 'created')
  end
  handle_asynchronously :create_news_update

  def new_question_notification
    # Notifies users who subscribed to receive email notifications
    # on at least one of the question's topics (unless the question
    # was actually created by the user).
    visited_subscriber_id = {}
    subscriber_ids_with_topics = []
    self.topics.each do |topic|
      topic.email_subscriber_ids.each do |user_id|
        if !visited_subscriber_id[user_id]
          visited_subscriber_id[user_id] = true
          subscriber_ids_with_topics << [user_id, topic]
        end
      end
    end

    subscriber_ids_with_topics.each do |user_id, topic|
      user = User.find_by_id(user_id)
      next if user == self.user
      Notifier.delay.new_question(user, self.group, self, topic)
      Notification.create!(:user => user,
                           :event_type => "new_question",
                           :origin => self.user,
                           :reason => self,
                           :topic => topic)
    end
  end
  handle_asynchronously :new_question_notification

  def requested_users
    AnswerRequest.query(:question_id => self.id).
      map(&:invited)
  end

  def update_topics_questions_count
    self.topics.each(&:increment_questions_count)
  end

  def increment_user_topic_questions_count
    UserTopicInfo.question_added!(self)
  end

  def decrement_user_topic_questions_count
    UserTopicInfo.question_removed!(self)
  end

  protected
  def update_answer_count
    self.answers_count = self.answers.where(:banned => false).count
    votes_average = 0
    self.votes.each {|e| votes_average+=e.value }
    self.votes_average = votes_average

    self.votes_count = self.votes.count
  end

  def update_autocomplete_keywords
    if !title.nil?
      @autocomplete_keywords = title.split(/\W/).
        delete_if {|w| w.empty?}.map &:downcase
    end
  end

  def add_question_author_to_watchers
    self.watchers = [self.user_id]
  end

  def search_entry
    topic = self.topics.first
    {
      :id => self.id,
      :title => self.title,
      :topic => topic ? topic.title : '',
      :entry_type => "Question"
    }
  end

  def needs_to_update_search_index?
    self.title_changed? || super
  end

  def adjust_newlines
    self.body = self.body.to_lf
  end

  # Post this question on the Twitter accounts of every topic.
  def post_on_twitter
    self.topics.each do |topic|
      topic.delay.post_on_twitter(self) if topic.external_account.present?
    end
  end
end
