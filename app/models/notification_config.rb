class NotificationConfig
  include MongoMapper::EmbeddedDocument

  key :_id, String

  key :give_advice, Boolean, :default => false
  key :activities, Boolean, :default => true
  key :reports, Boolean, :default => false
  key :new_answer, Boolean, :default => true
end
