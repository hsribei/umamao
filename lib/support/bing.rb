module Support::Bing
  extend self

  def search(string)
    if (bing_response = Bing.web(string).web).total > 1
      bing_response.results
    end
  end
end
