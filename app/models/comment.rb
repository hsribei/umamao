class Comment
  include MongoMapper::Document
  include Support::Voteable

  key :_id, String
  key :_type, String
  key :body, String, :required => true
  key :language, String, :default => 'pt-BR'
  key :banned, Boolean, :default => false
  attr_accessor :created_together_with_search_result

  timestamps!

  key :user_id, String, :index => true
  belongs_to :user

  key :group_id, String, :index => true
  belongs_to :group

  key :commentable_id, String
  key :commentable_type, String
  belongs_to :commentable, :polymorphic => true

  has_many :notifications, :as => "reason", :dependent => :destroy

  validates_presence_of :user

  validate :disallow_spam

  before_save :adjust_newlines
  after_create :new_comment_notification,
               :unless => :created_together_with_search_result

  def ban
    self.collection.update({:_id => self.id}, {:$set => {:banned => true}},
                                               :upsert => true)
  end

  def self.ban(ids)
    ids.each do |id|
      self.collection.update({:_id => id}, {:$set => {:banned => true}},
                                                       :upsert => true)
    end
  end

  def can_be_deleted_by?(user)
    ok = (self.user_id == user.id && user.can_delete_own_comments_on?(self.group)) || user.mod_of?(self.group)
    if !ok && user.can_delete_comments_on_own_questions_on?(self.group) && (q = self.find_question)
      ok = (q.user_id == user.id)
    end

    ok
  end

  def find_question
    question = nil
    if self.commentable.kind_of?(Question)
      question = self.commentable
    elsif self.commentable.respond_to?(:question)
      question = self.commentable.question
    end

    question
  end

  def question_id
    question_id = nil

    if self.commentable_type == "Question"
      question_id = self.commentable_id
    elsif self.commentable_type == "Answer"
      question_id = self.commentable.question_id
    elsif self.commentable.respond_to?(:question)
      question_id = self.commentable.question_id
    end

    question_id
  end

  # List all users that should be notified about this comment. If the
  # commented entry is a question, we notify the author and every
  # commenter of that question. Otherwise, the entry is an answer, and
  # we notify the related question's author, the answer's author and
  # every commenter of that answer.
  def users_to_notify
    Set.new.tap{ |users|
      if self.commentable.is_a? Question
        users << self.commentable.user
        users.merge self.commentable.comments.map(&:user)
      else
        if (question = self.find_question)
          users << question.user
        end
        users << self.commentable.user
        users.merge self.commentable.comments.map(&:user)
      end

      users.delete self.user
    }
  end

  protected
  def disallow_spam
    eq_comment = Comment.first({ :body => self.body,
                                  :commentable_id => self.commentable_id
                                })


    valid = (eq_comment.nil? || eq_comment.id == self.id)
    if !valid
      self.errors.add(:body, "Your comment looks like spam.")
    end
  end

  def new_comment_notification
    if (question = self.find_question)
      self.users_to_notify.each do |recipient|
        email = recipient.email
        if email.present? && recipient.notification_opts.new_answer
          Notifier.delay.new_comment(recipient, question.group, self, question)
        end
        Notification.create!(:user => recipient,
                             :event_type => "new_comment",
                             :origin => self.user,
                             :reason => self)
      end
    end
  end
  handle_asynchronously :new_comment_notification

  def adjust_newlines
    self.body = self.body.to_lf
  end
end
