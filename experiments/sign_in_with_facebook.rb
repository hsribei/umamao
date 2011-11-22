ab_test 'Sign in with Facebook' do
  alternatives :regular_sign_up, :facebook_sign_in
  metrics :signed_up_action
  identify { |c| c.identifier(:preserve_identity => true) }
  complete_if { true }
end
