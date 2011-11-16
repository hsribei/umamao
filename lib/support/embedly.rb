require 'uri'

module Support
  class Embedly

    USER_AGENT = 'Mozilla/5.0 (X11; Linux i686; rv:6.0) Gecko/20100101 Firefox/6.0'

    def initialize(uri)
      key =  AppConfig.embedly['key']
      @uri = URI("http://api.embed.ly/1/oembed?key=#{key}&url=#{URI.encode(uri)}")
    rescue URI::InvalidURIError
      add_error(@fetcher, $!)
    end

    def title
      response['title']
    end

    def response
      return @response if @response
      res = Net::HTTP.get_response(@uri)
      @response = if res.is_a?(Net::HTTPSuccess)
                    JSON.parse(res.body)
                  else
                    {}
                  end
    end
  end
end
