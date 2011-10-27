module Support::Bing
  extend self

  def search(string, options = { :max_results => 5 })
    results = if (bing_response = Bing.web(string).web).total > 1
                bing_response.results.first(options[:max_results])
              else
                []
              end
    { :results => results, :total_results_count => bing_response.total }
  end
end
