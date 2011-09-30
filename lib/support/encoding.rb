require 'iconv'

module Support
  module Encoding
    def force_encoding(string, encoding)
      Iconv.conv("#{encoding}//translit//ignore", encoding, string)
    end
  end
end
