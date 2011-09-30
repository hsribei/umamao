require 'iconv'

module Support
  module Encoding
    def scrub_invalid_chars(string)
      string.unpack("C*").pack("U*")
    end
  end
end
