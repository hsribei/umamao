ab_test 'News item search results helpers' do
  alternatives :answer, :search_results
  metrics :commented, :voted, :used_today
  identify { |c| c.identifier }
end
