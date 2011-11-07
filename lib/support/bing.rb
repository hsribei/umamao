module Support::Bing
  extend self

  def search(string, options = { :max_results => 5 })
    response_data = Bing.web(string)
    results = if response_data['Web'] && (bing_response = response_data.web).total > 1
                bing_response.results.first(options[:max_results])
              else
                []
              end
    { :results => results,
      :total_results_count => (bing_response && bing_response.total).to_i }
  end
end
