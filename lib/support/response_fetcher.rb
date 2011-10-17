require 'uri'

module Support
  class ResponseFetcher
    class TooManyRedirectionsError < StandardError; end
    class EmptyResponse; def body; nil; end; end

    POSSIBLE_FETCH_ERRORS = [Errno::ECONNREFUSED,
                             Errno::ECONNRESET,
                             Errno::ETIMEDOUT,
                             Net::HTTPServerException,
                             Net::HTTPBadResponse,
                             Net::HTTPFatalError,
                             SocketError,
                             Timeout::Error,
                             TooManyRedirectionsError,
                             URI::InvalidURIError]
    REDIRECTION_LIMIT = 5
    TIMEOUT = 10

    include ActiveSupport::Inflector

    attr_reader :uri

    def initialize(uri, params)
      @fetcher = params[:fetcher]
      @uri = URL.new(uri).uri
    rescue URI::InvalidURIError
      add_error(@fetcher, $!)
    end

    def fetch
      request_uri = lambda do |uri|
        if uri.respond_to?(:request_uri)
          uri.request_uri
        else
          uri.query.present? ? uri.path + '?' + uri.query : uri.path
        end
      end
      fetcher = lambda do |uri, redirections_left|
        raise TooManyRedirectionsError if redirections_left == 0
        parsed_uri = URI.parse(uri)
        request = Net::HTTP::Get.new(request_uri.call(parsed_uri))
        http = Net::HTTP.new(parsed_uri.host || 'http', parsed_uri.port)
        http.open_timeout = http.read_timeout = TIMEOUT
        if parsed_uri.port == 443
          http.use_ssl = true
          # http://jamesgolick.com/2011/2/15/verify-none..html
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        case response = http.request(request)
        when Net::HTTPSuccess then response
        when Net::HTTPRedirection then fetcher.call(response['location'],
                                                    redirections_left - 1)
        else response.error!
        end
      end
      response = fetcher.call(uri.to_s, REDIRECTION_LIMIT)
      clean_body = begin
                     ActiveSupport::Multibyte::Unicode.tidy_bytes(response.body)
                   rescue StandardError
                     ActiveSupport::Multibyte::Unicode.tidy_bytes(response.body,
                                                                  true)
                   end
      response.instance_variable_set(:@body, clean_body)
      response
    rescue *POSSIBLE_FETCH_ERRORS
      add_error(@fetcher, $!) if $!.is_a?(URI::InvalidURIError)
      EmptyResponse.new
    end

  private

    def add_error(fetcher, error)
      constant2symbol = lambda do |constant|
        underscore(constant.to_s.delete(':'))
      end

      fetcher.errors.add_to_base(I18n.t(constant2symbol.call(error.class),
                                        :scope =>
                                          [:activerecord,
                                           :errors,
                                           constant2symbol.call(fetcher.class)]))
    end
  end
end
