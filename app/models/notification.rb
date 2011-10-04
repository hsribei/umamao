# Notification messages shown to users.

class Notification
  include MongoMapper::Document

  timestamps!

  # The notification's recipient
  belongs_to :user

  key :event_type, String, :required => true

  # The user who caused the notification.
  key :origin_id, String
  belongs_to :origin, :class_name => "User"

  # The entry which provoked the notification.
  key :reason_id
  key :reason_type
  belongs_to :reason, :polymorphic => true

  key :topic_id, ObjectId
  belongs_to :topic

  def unread?
    !self.user.last_read_notifications_at ||
      self.user.last_read_notifications_at < self.created_at
  end

  # Return the question related to this notification, if it exists.
  def question
    case self.event_type
    when "new_answer"
      self.reason.question
    when "new_search_result"
      self.reason.question
    when "new_comment"
      self.reason.find_question
    when "new_question"
      self.reason
    when "new_answer_request"
      self.reason.question
    end
  end
end
