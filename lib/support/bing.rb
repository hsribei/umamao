module Support::Bing
  extend self

  def search(string, options = { :max_results => 5, :timeout => 1 })
    empty_response = { :results => [], :total_results_count => 0 }
    timeout(options[:timeout]) do
      response_data = Bing.web(string)
      if response_data && response_data['Web'] && (bing_response = response_data.web).total > 1
        results = bing_response.results.first(options[:max_results])
        { :results => results, :total_results_count => bing_response.total.to_i }
      else
        empty_response
      end
    end
  rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Timeout::Error
    empty_response
  end
end
