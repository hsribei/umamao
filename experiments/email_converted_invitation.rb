ab_test 'Email converted invitation' do
  metrics :converted_invitation
  identify { |c| c.identifier(:inviter => true) }
end
