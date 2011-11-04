ab_test 'News item search results helpers' do
  alternatives :answer, :search_results
  metrics :search_results_news_items
  identify { |c| c.identify_vanity }
end
