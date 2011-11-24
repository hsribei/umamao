class UserQuestionInfo
  include MongoMapper::Document

  key :user_id, String, :required => true, :index => true
  belongs_to :user

  key :question_id, String, :required => true, :index => true
  belongs_to :question

  key :last_visited_at, Time
end
