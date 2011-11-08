ab_test 'Answer with form position' do
  alternatives :below, :above
  metrics :new_search_result
  identify { |c| c.identify_vanity }
end
