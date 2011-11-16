class NewsItem
  include MongoMapper::Document

  key :recipient_id, :required => true
  key :recipient_type, :required => true
  belongs_to :recipient, :polymorphic => true

  key :news_update_id, ObjectId, :required => true
  belongs_to :news_update
  key :news_update_entry_type, String
  key :open_question, Boolean

  # origin is the reason why this update made its way to the
  # recipient: a user, topic or question she was following.
  key :origin_id, :required => true
  key :origin_type, :required => true
  belongs_to :origin, :polymorphic => true

  key :visible, Boolean, :default => true

  validates_uniqueness_of :recipient_id, :scope => :news_update_id

  ensure_index([[:recipient_id, 1], [:created_at, -1]])

  timestamps!

  # Notifies each recipient of a news update. The creation date will
  # be the same as the news update's.
  def self.from_news_update!(news_update)
    origins = [news_update.author] + news_update.entry.topics
    notify!(news_update, news_update.author,
            news_update.author, news_update.created_at)
    notified_users = Set.new [news_update.author]

    # do not notify users that ignore any topic on that entry
    notified_users += User.ignorers(news_update.entry.topics)

    origins.each do |origin|
      origin.followers.each do |follower|
        next if notified_users.include?(follower)
        notify!(news_update, follower, origin, news_update.created_at)
        notified_users << follower
      end
    end

    news_update.entry.topics.each do |topic|
      notify!(news_update, topic, topic, news_update.created_at)
    end

    self.delay.update_is_open(news_update)
  end

  def self.update_is_open(news_update)
    news_update.news_items.each do |ni|
      ni.news_update_entry_type = news_update.entry_type
      if  ni.news_update_entry_type == "Question"
        ni.open_question = news_update.entry.is_open
      end
      ni.save
    end
  end

  # Notifies a single recipient. Allows us to specify when the item
  # was created.
  def self.notify!(news_update, recipient, origin, created_at = nil)
    news_item = new(:news_update => news_update,
               :recipient => recipient,
               :origin => origin)

    if recipient.is_a? User
      if news_update.entry.is_a?(Question) || news_update.entry.is_a?(SearchResult)
        if news_update.entry.is_a?(Question)
          question = news_update.entry
        else
          question = news_update.entry.question
        end
        question.topic_ids.each do |topic_id|
          return if recipient.ignored_topic_ids.include?(topic_id)
        end
      end
    end

    if recipient.is_a? Topic
      news_item.recipient_type = "Topic"
    end

    if origin.is_a? Topic
      news_item.origin_type = "Topic"
    end

    if created_at
      news_item.created_at = created_at
    end

    news_item.save!
    news_item
  end

  def title
    t = self.news_update.entry.title
    if t.blank? && news_update.entry_type == "SearchResult"
      t = self.news_update.entry.url
    end
    t
  end

  def hide!
    self.set(:visible => false)
  end

  def show!
    self.set(:visible => true)
  end

  # if the news_item doesn't include a ignored topic and
  # it's not a question that should be hidden
  def should_be_hidden?(ignored_topic_ids = [])
    entry = self.news_update.entry
    (entry.topic_ids & ignored_topic_ids).any?
  end
end
