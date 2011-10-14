module Support
  module Xpath
    def case_insensitive_xpath(params)
      "translate(@#{params[:attribute].to_s},'#{('A'..'Z').to_a.to_s}'," <<
        "'#{('a'..'z').to_a.to_s}')='#{params[:value].to_s}'"
    end
  end
end
