require 'uri'

module Support
  class URL
    ACCEPTED_SCHEMES = %w[http https]

    attr_accessor :uri

    def initialize(url)
      parsed_uri = URI.parse(url)
      self.uri = if parsed_uri.scheme && parsed_uri.host && parsed_uri.port
                   ACCEPTED_SCHEMES.include?(parsed_uri.scheme) ? parsed_uri :
                                                                  nil
                 else
                   URI.parse(url.insert(0, parsed_uri.port == 443 ? 'https://' :
                                                                    'http://'))
                 end
      scrub_hash if twitter? && parsed_uri.fragment
    rescue URI::InvalidURIError
      raise
    end

    def twitter?
      uri.host == 'twitter.com'
    end

    def scrub_hash
      uri.path << uri.fragment.delete('!')
      uri.fragment = nil
    end
  end
end
