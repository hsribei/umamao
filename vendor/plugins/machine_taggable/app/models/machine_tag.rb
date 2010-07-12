class MachineTag
  include MongoMapper::Document

  key :_id, String
  key :namespace, String, :required => true
  key :key, String, :required => true
  key :value, String, :required => true

  key :question_id, String, :index => true
  belongs_to :question

end
