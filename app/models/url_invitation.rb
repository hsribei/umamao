class UrlInvitation
  include MongoMapper::Document

  MAXIMUM_SIGN_UPS = 50

  key :clicks_count, Integer, :default => 0
  key :sign_ups_count, Integer, :default => 0
  key :ref, String, :unique => true, :required => true, :length => 4

  key :invitee_ids, Array
  many :invitees, :in => :invitee_ids, :class_name => 'User'

  key :inviter_id, String
  belongs_to :inviter, :class_name => 'User'

  timestamps!

  validate :number_of_invitees_should_be_less_or_equal_than_50

  def self.generate(user)
    begin ref = SecureRandom.hex(2); end while find_by_ref(ref)
    UrlInvitation.create(:inviter => user, :ref => ref)
  end

  def increment_clicks
    update_attributes(:clicks_count => clicks_count + 1)
  end

  def add_invitee(invitee)
    unless invitee_ids.include?(invitee.id)
      update_attributes(:invitee_ids => invitee_ids << invitee.id,
                        :sign_ups_count => sign_ups_count + 1)
    end
  end

  def invites_left
    MAXIMUM_SIGN_UPS - sign_ups_count
  end

private

  def number_of_invitees_should_be_less_or_equal_than_50
    if sign_ups_count > MAXIMUM_SIGN_UPS
      errors.add(:sign_ups_count,
                 I18n.t(:less_or_equal,
                        :scope => [:url_invitations, :messages],
                        :number => MAXIMUM_SIGN_UPS))
    end
  end
end
