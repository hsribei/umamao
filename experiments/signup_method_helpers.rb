ab_test 'Signup methods helpers' do
  alternatives :welcome_landing, :users_new
  metrics :signup_method
  identify { |c| c.identify_vanity }
end
