class Suggestion
  include MongoMapper::Document

  before_destroy :propagate_destruction

  key :user_id, :required => true, :index => true
  belongs_to :user

  key :entry_id, :required => true
  key :entry_type, :required => true
  belongs_to :entry, :polymorphic => true

  ensure_index([[:entry_id, 1], [:entry_type, 1]])

  key :reason, String

  timestamps!

  def reject!
    self.destroy
  end

  def propagate_destruction
    user && user.remove_suggestion(entry)
  end
  handle_asynchronously :propagate_destruction
end
