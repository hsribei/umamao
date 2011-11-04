ab_test 'Sign in with Facebook' do
  alternatives :regular_signup, :facebook_sign_in
  metrics :signup_action
end
