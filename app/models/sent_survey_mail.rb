class SentSurveyMail
  include MongoMapper::Document

  key :user_id, String
  belongs_to :user

  timestamps!

  validates_presence_of :user
end
