ab_test 'Email converted invitation' do
  metrics :converted_invitation
  identify { |c| c.identify_vanity(:inviter => true) }
end
