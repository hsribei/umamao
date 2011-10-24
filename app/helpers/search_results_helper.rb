module SearchResultsHelper
  def trackable_search_result_url(search_result)
    site = "http://#{AppConfig.domain}#{":#{AppConfig.port}" if AppConfig.port}"
    "#{site}/g/?url=#{CGI.escape(search_result.url)}&search_result_id=#{search_result.id}"
  end
end
