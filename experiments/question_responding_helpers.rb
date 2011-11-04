ab_test 'Question responding helpers' do
  alternatives :none, :google_search_link, :bing_results
  metrics :question_posted
  identify { |c| c.identify_vanity }
end
