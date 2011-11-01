class NewsUpdate
  include MongoMapper::Document

  key :author_id, String, :required => true, :index => true
  belongs_to :author, :class_name => 'User'

  key :entry_id, :required => true
  key :entry_type, :required => true
  belongs_to :entry, :polymorphic => true

  has_many :news_items, :dependent => :destroy

  validates_uniqueness_of :entry_id

  key :action, String, :required => true, :in => %w[created upvoted]

  timestamps!

  after_create :create_news_items

  def on_question_status_change(status)
    self.news_items.each do |ni|
      ni.set(:open_question => status)
    end
  end

  def create_news_items
    NewsItem.from_news_update!(self)
  end
  handle_asynchronously :create_news_items

  def hide!
    self.news_items.each do |ni|
      ni.hide!
    end
  end

  def show!
    self.news_items.each do |ni|
      ni.show!
    end
  end
end
