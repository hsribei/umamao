class UserTopicInfo
  include MongoMapper::Document

  key :user_id, String, :required => true, :index => true
  belongs_to :user

  key :topic_id, ObjectId, :required => true, :index => true
  belongs_to :topic

  key :followed_at, Time
  key :ignored_at, Time
  key :answers_count, Integer, :default => 0
  key :questions_count, Integer, :default => 0
  key :votes_balance, Integer, :default => 0

  after_create :update_counts

  validates_uniqueness_of :user_id, :scope => [:topic_id]
  ensure_index([[:user_id, 1], [:topic_id, 1]])
  ensure_index([[:topic_id, 1], [:votes_balance, -1]])

  timestamps!

  def followed?
    self.followed_at.present?
  end

  def follow
    self.unignore
    self.followed_at ||= Time.now
  end

  def follow!
    self.follow
    self.save!
  end

  def unfollow
    self.followed_at = nil
  end

  def unfollow!
    self.unfollow
    self.save!
  end

  def ignored?
    self.ignored_at.present?
  end

  def ignore
    self.unfollow
    self.ignored_at ||= Time.now
  end

  def ignore!
    self.ignore
    self.save!
  end

  def unignore
    self.ignored_at = nil
  end

  def unignore!
    self.unignore
    self.save!
  end

  def self.question_added!(question)
    question.topics.each do |topic|
      update_question_topic(question.user, topic)
    end
  end

  def self.question_removed!(question)
    question.topics.each do |topic|
      update_question_topic(question.user, topic, -1)
    end
  end

  def self.answer_added!(answer)
    return if answer.question.nil?

    answer.question.topics.each do |topic|
      update_answer_topic(answer.user, topic)
    end
  end

  def self.answer_removed!(answer)
    answer.question.topics.each do |topic|
      update_answer_topic(answer.user, topic, -1)
    end
  end

  def self.reset_answers_count!
    self.find_each do |user_topic|
      user_topic.answers_count = 0
      user_topic.save
    end
  end

  def self.vote_added!(answer, vote)
    answer.question.topics.each do |topic|
      increment_votes_balance(answer.user, topic, vote)
    end
  end

  def self.vote_removed!(answer, vote)
    answer.question.topics.each do |topic|
      increment_votes_balance(answer.user, topic, -vote)
    end
  end

  def self.update_vote_balance!(answer)
    return if answer.question.nil?

    answer.question.topics.each do |topic|
      self.update_votes_balance(answer.user, topic, answer.votes_average)
    end
  end

  def self.reset_votes_balance!
    self.find_each do |user_topic|
      user_topic.votes_balance = 0
      user_topic.save
    end
  end

  def self.question_classified!(question, topic)
    # Update questions and answers_count and votes_balance
    self.update_question_topic(question.user, topic)

    question.answers.each do |answer|
      self.update_answer_topic(answer.user, topic)
      self.update_votes_balance(answer.user, topic, answer.votes_average)
    end
  end

  def self.question_unclassified!(question, topic)
    # Update questions and answers_count and votes_balance
    update_question_topic(question.user, topic, -1)

    question.answers.each do |answer|
      update_answer_topic(answer.user, topic, -1)
      update_votes_balance(answer.user, topic, -answer.votes_average)
    end
  end

  def update_counts
    answers = Answer.query(:user_id => user.id).fields([:question_id]).
      select do |a|
        a.question && a.question.topic_ids.include?(self.topic_id)
      end

    self.answers_count = answers.size
    self.votes_balance = answers.map(&:votes_average).inject(0, &:+)
    self.questions_count =
      Question.count(:user_id => self.user_id, :topic_id => self.topic_id)
  end

  def self.find_by_user_id_and_topic_id(user_id, topic_id)
    UserTopicInfo.first(:user_id => user_id, :topic_id => topic_id)
  end

  private

  def self.update_question_topic(user, topic, increment=1)
    user_topic = UserTopicInfo.first(:topic_id => topic.id,
                                     :user_id => user.id)
    if user_topic
      user_topic.questions_count += increment
      user_topic.save
    else
      increment = [increment, 0].max
      UserTopicInfo.create(:topic_id => topic.id, :user_id => user.id,
                           :questions_count => increment)
    end
  end

  def self.update_answer_topic(user, topic, increment=1)
    user_topic = UserTopicInfo.first(:topic_id => topic.id,
                                     :user_id => user.id)
    if user_topic
      user_topic.answers_count += increment
      user_topic.save
    else
      increment = [increment, 0].max
      UserTopicInfo.create(:topic_id => topic.id, :user_id => user.id,
                           :answers_count => increment)
    end
  end

  def self.increment_votes_balance(user, topic, increment)
    user_topic = UserTopicInfo.first(:topic_id => topic.id,
                                     :user_id => user.id)

    if user_topic
      user_topic.votes_balance += increment
      user_topic.save
    else
      UserTopicInfo.create(
        :topic_id => topic.id, :user_id => user.id, :votes_balance => increment)
    end
  end

  def self.update_votes_balance(user, topic, vote)
    user_topic = UserTopicInfo.first(:topic_id => topic.id,
                                     :user_id => user.id)

    if user_topic
      user_topic.votes_balance = vote
      user_topic.save
    else
      UserTopicInfo.create(
        :topic_id => topic.id, :user_id => user.id, :votes_balance => vote)
    end
  end
end
