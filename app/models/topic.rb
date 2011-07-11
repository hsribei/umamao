class Topic
  include MongoMapper::Document
  include MongoMapperExt::Slugizer
  include MongoMapperExt::Filter
  include Support::Versionable
  include Support::Search::Searchable

  # It seems that MM doesn't do this automatically
  ensure_index :_type

  key :title, String, :required => true, :index => true, :unique => true
  filterable_keys :title
  key :description, String
  key :questions_count, :default => 0
  ensure_index([[:questions_count, -1]])

  key :updated_by_id, String
  belongs_to :updated_by, :class_name => "User"

  key :followers_count, :default => 0, :index => true

  slug_key :title, :unique => true, :min_length => 3

  has_many :news_items, :foreign_key => :recipient_id, :dependent => :destroy
  has_many :generated_news_items, :class_name => "NewsItem",
    :foreign_key => :origin_id, :dependent => :destroy

  has_many :notifications, :dependent => :destroy
  has_many :user_topic_info, :dependent => :destroy

  key :related_topic_ids, :default => []
  has_many :related_topics, :class_name => "Topic",
    :in => :related_topic_ids
  key :related_topics_count, Hash, :default => {}

  key :freebase_mids, Array
  key :freebase_guid, String

  key :wikipedia_pt_id, String
  key :wikipedia_pt_key, String
  key :wikipedia_import_status, String


  key :wikipedia_description_imported_at, Time

  key :types, Array

  key :email_subscriber_ids,  Array
  has_many :email_subscribers, :class_name => 'User', :in => :email_subscriber_ids

  key :allow_question_lists, Boolean, :default => false

  # We need to pass the foreign key here to make this association work
  # with topic subclasses.
  has_one :external_account, :class_name => "TopicExternalAccount",
    :foreign_key => :topic_id, :dependent => :destroy

  timestamps!

  versionable_keys :title, :description

  before_validation :trim_spaces

  before_save :generate_slug

  after_destroy :remove_from_questions
  after_destroy :remove_from_question_versions
  after_destroy :remove_from_suggestions

  class Helper
    include Singleton
    include ActionView::Helpers::TextHelper
  end

  # Wikipedia can be accessed by article_id using
  # http://pt.wikipedia.org/w/index.php?curid=#{wikipedia_pt_id}
  # and by article_name using
  # http://pt.wikipedia.org/wiki/#{article_name}
  def wikipedia_pt_url
    "http://pt.wikipedia.org/wiki/#{wikipedia_pt_key}" if wikipedia_pt_key
  end

  def wikipedia_pt_id_url
    "http://pt.wikipedia.org/w/index.php?curid=#{wikipedia_pt_id}" if wikipedia_pt_id
  end

  # Removes spaces from the beginning, the end and inbetween words
  # from the title
  def trim_spaces
    return if self.title.blank?
    self.title.strip!
    self.title.gsub!(/\s+/, " ")
  end

  # Takes array of strings and returns array of topics with matching
  # titles, creating new topics for titles that are not found.
  def self.from_titles!(titles)
    return [] if titles.blank?
    self.all(:title.in => titles).tap { |topics|
      if topics.size != titles.size
        new_titles = titles - topics.map(&:title)
        new_topics = new_titles.map {|t| self.create(:title => t) }
        topics.push(*new_topics)
      end
    }
  end

  def ignorers
    UserTopicInfo.fields([:user_id]).
      query(:topic_id => self.id, :ignored_at.ne => nil).map(&:user)
  end

  # FIXME: refactor
  def ignorer_ids
    UserTopicInfo.fields([:user_id]).
      query(:topic_id => self.id, :ignored_at.ne => nil).map(&:user_id)
  end

  def name
    title
  end

  # Post a question on this topic's Twitter account.
  #
  # FIXME: Ideally this should be put on a mailer-like class outside
  # the model.
  def post_on_twitter(question)
    Twitter.configure do |config|
      config.consumer_key = AppConfig.twitter['key']
      config.consumer_secret = AppConfig.twitter['secret']
      config.oauth_token = external_account.credentials['token']
      config.oauth_token_secret = external_account.credentials['secret']
    end

    client = Twitter::Client.new
    bitly = Bitly.new(AppConfig.bitly[:username], AppConfig.bitly[:apikey])
    url = Rails.application.routes.
      url_helpers.question_url(question,
                               :host => AppConfig.domain)
    short_url = bitly.shorten(url).short_url
    body = Helper.instance.truncate(question.title,
                                    :length => 140 - short_url.size - 1)
    client.update("#{body} #{short_url}")
    true
  end

  def find_related_topics
    topic_counts = {}

    Question.query(:topic_ids => self.id).each do |question|
      question.topics.each do |related_topic|
        next if related_topic == self
        topic_counts[related_topic.id] =
          (topic_counts[related_topic.id] || 0) + 1
      end
    end

    sorted_topics_count = topic_counts.to_a.sort{|a,b| -(a[1] <=> b[1])}[0..9]
    self.related_topic_ids = sorted_topics_count.map(&:first)
    self.related_topics_count =
      Hash[sorted_topics_count.map { |k,v| [k.to_s,v] }]

    self.related_topics
  end

  # Return a Hash [Topic, Integer] giving the co-occurrence of
  # questions between self and the others.
  def related_topics_with_count
    unordered_topics = Topic.query(:id.in => related_topics_count.keys)
    unordered_topics.sort_by { |t| -(self.related_topics_count[t.id.to_s]) }.
      map { |t| [t, self.related_topics_count[t.id.to_s]] }
  end

  def questions
    Question.query(:topic_ids => self.id)
  end

  # The order in which the questions should be listed.
  def default_question_order
    :created_at.desc
  end

  # We make this association by hand because declaring it as usual was
  # screwing up our development server (probably a dependency resolver
  # bug).
  def question_lists
    QuestionList.query(:main_topic_id => self.id)
  end

  # Return the question lists that are classified under this topic.
  def indirect_question_lists
    QuestionList.query("$or" => [{:topic_ids => self.id},
                                 {:main_topic_id => self.id}])
  end

  # Add a follower to topic.
  def add_follower!(user)
    if user_topic_info = UserTopicInfo.first(:topic_id => self.id,
                                        :user_id => user.id)
      unless user_topic_info.followed?
        user_topic_info.follow!
        self.increment(:followers_count => 1)
        user.unignore_topic!(self)
      end
    else
      UserTopicInfo.create(:topic_id => self.id, :user_id => user.id,
                           :followed_at => Time.now)
      self.increment(:followers_count => 1)
      user.unignore_topic!(self)
    end
  end

  # Remove a follower from topic.
  def remove_follower!(user)
    if user_topic_info = UserTopicInfo.first(:topic_id => self.id,
                                        :user_id => user.id,
                                        :followed_at.ne => nil)
      user_topic_info.followed_at = nil
      if self.email_subscribers.include?(user)
        self.email_subscriber_ids.delete(user.id)
      end
      self.increment(:followers_count => -1)
      if self.save!
        user_topic_info.save
      end
    end
  end

  # Merges other to self: self receives every question, questions_count, follower,
  # followers_count and news update from other. Destroys other. Cannot be undone.
  def merge_with!(other)
    if id == other.id
      raise "Cannot merge topic into itself."
    end

    new_attributes = self.attributes

    if (self.class != Topic || other.class != Topic) &&
        !(self.class <= other.class)
      # We shoudn't attempt to merge two topics of different
      # specific classes.
      raise("Cannot merge instance of #{other.class} " +
            "into an instance of #{self.class}")
    end

    # Augment self's attributes with ones defined in other that aren't
    # present in self. Note that this is slightly different from Hash#merge.
    other.attributes.each do |k, v|
      if v.present? && new_attributes[k].blank?
        new_attributes[k] = v
      end
    end
    self.update_attributes(new_attributes)

    self.delay.merge_external_entities_from other

    save
  end

  def merge_external_entities_from(other)
    self.merge_questions_from other
    self.merge_question_lists_from other
    self.merge_invitations_from other
    self.merge_group_invitations_from other
    self.merge_user_info_from other
    other.destroy
    save
  end

  def merge_questions_from(other)
    Question.find_each(:topic_ids => other.id) do |q|
      q.classify! self
    end

    # Update questions' history
    Question.find_each do |q|
      changed = false
      q.versions.each do |v|
        topic_ids = v.data[:topic_ids]
        if topic_ids.include? other.id
          topic_ids.delete(other.id)
          unless topic_ids.include?(other.id)
            topic_ids << self.id
            changed = true
          end
        end
      end
      q.save! if changed
    end
  end

  def merge_question_lists_from(other)
    other.question_lists.each do |question_list|
      question_list.main_topic_id = self.id
      question_list.save!
    end
  end

  def merge_invitations_from(other)
    Invitation.query(:topic_ids => other.id) do |invitation|
      invitation.topic_ids.delete other.id
      invitation.topic_ids << self.id
      invitation.save!
    end
  end

  def merge_group_invitations_from(other)
    GroupInvitation.query(:topic_ids => other.id) do |invitation|
      invitation.topic_ids.delete other.id
      invitation.topic_ids << self.id
      invitation.save!
    end
  end

  def merge_user_info_from(other)
    UserTopicInfo.find_each(:topic_id => other.id) do |user_topic_other|
      if user_topic = UserTopicInfo.first(:topic_id => self.id,
                                          :user_id => user_topic_other.user.id)
        followed_at = []
        followed_at << user_topic.followed_at if user_topic.followed?
        followed_at << user_topic_other.followed_at if user_topic_other.
          followed?
        user_topic.followed_at = followed_at.min if followed_at.present?

        ignored_at = []
        ignored_at << user_topic.ignored_at if user_topic.ignored?
        ignored_at << user_topic_other.ignored_at if user_topic_other.
          ignored?
        user_topic.ignored_at = ignored_at.min if ignored_at.present? &&
          !user_topic.followed_at

         if user_topic.save!
           user_topic_other.destroy
         end
      else
        user_topic = user_topic_other
        user_topic.topic = self
        user_topic.save!
      end

      return true

    end

    UserTopicInfo.find_each(:topic_id => self.id) do |user_topic|
     user_topic.update_counts
    end

    self.followers_count = UserTopicInfo.count(:topic_id => self.id,
                                               :followed_at.ne => nil)

  end

  def remove_from_questions
    Question.find_each(:topic_ids => self.id) do |question|
      question.topic_ids.delete(self.id)
      question.save!
    end
  end

  # Iterates through each question removing this topic from every past
  # version. This is very slow and should be used with care, but as
  # topics aren't deleted that often, this is not too much of an
  # issue.
  def remove_from_question_versions
    Question.query.each do |question|
      next if question.versions.blank?
      changed = false
      question.versions.each do |version|
        if version.data[:topic_ids].include? self.id
          changed = true
          version.data[:topic_ids].delete self.id
        end
      end
      question.save! if changed
    end
  end

  # Removes topic from user suggestions and ignored topics. This
  # method is delayed in production and staging environments.
  def remove_from_suggestions
    Suggestion.query(:entry_id => self.id,
                     :entry_type => "Topic").each do |suggestion|
      if suggestion.user.present?
        suggestion.user.remove_suggestion(suggestion)
        suggestion.user.save
      end
    end

    # TODO: We should replace this with a better query, but this would
    # incur on changes in the models. Right now this isn't too much of
    # an issue since topics are rarely deleted.
    User.query(:select => :suggestion_list).each do |user|
      if user.suggestion_list
        user.suggestion_list.uninteresting_topic_ids.delete(self.id)
        user.save
      end
    end
  end

  def unanswered_questions_count
    Question.count(:topic_ids => self.id, :banned => false,
                   :closed => false, :answered_with_id => nil)
  end

  # WARNING: The search index update isn't atomic: the models will be
  # consistent, but the search index might not reflect the actual
  # questions_count.
  def increment_questions_count(step = 1)
    self.increment(:questions_count => step)
    self.questions_count += step
    self.update_search_index(true)
  end

  def search_entry
    {
      :id => self.id,
      :title => self.title,
      :entry_type => "Topic",
      :question_count => self.questions_count
    }
  end

  def needs_to_update_search_index?
    # Normally, we would need to check here whether questions_count
    # has changed or not, but since updates in questions_count are
    # done via mongo's atomic operations, we update this on questions.

    if self.title_changed?
      self.update_questions_search_entries
      true
    end
  end

  # Change the topic field on the search entries of this topic's
  # questions.
  def update_questions_search_entries
    Question.query(:topic_ids => self.id).each do |question|
      question.update_search_index(true)
    end
  end
  handle_asynchronously :update_questions_search_entries

  def follower_ids
    UserTopicInfo.fields([:user_id]).query(:topic_id => self.id,
                                           :followed_at.ne => nil).map(&:user_id)
  end

  def followers
    UserTopicInfo.fields([:user_id]).query(:topic_id => self.id,
                                           :followed_at.ne => nil).map(&:user)
  end

  def is_followed_by?(user)
    UserTopicInfo.first(:user_id => user.id, :topic_id => self.id,
                        :followed_at.ne => nil).present?
  end
end
