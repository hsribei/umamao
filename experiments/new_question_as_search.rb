ab_test 'New question as search' do
  alternatives :old_search_scheme, :new_search_scheme
  metrics :asked_question
  identify { |c| c.identify_vanity }
end
