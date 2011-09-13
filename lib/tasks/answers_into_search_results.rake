require 'uri'
require 'cgi'

namespace :data do
  namespace :migrate do
    desc 'Creates SearchResult objects from Answer objects'
    task :answers_into_search_results => :environment do
      include ApplicationHelper

      answer_url = lambda do |answer|
        URI::HTTP.build(:host => AppConfig.domain,
                        :port => AppConfig.port == 80 ? nil: AppConfig.port,
                        :path => "/questions/" <<
                                   "#{CGI.escape(answer.question.slug)}" <<
                                   "/answers/#{answer.id}")
      end

      Answer.all.each do |answer|
        begin
          search_result =
            SearchResult.create!(:url => answer_url.call(answer),
                                 :title => answer.title,
                                 :summary => truncate_words(answer.body),
                                 :user_id => answer.user_id,
                                 :question_id => answer.question_id)
        rescue MongoMapper::DocumentNotValid
          STDERR.puts "Error with SearchResult #{search_result.id}"
        rescue StandardError
          STDERR.puts $!
        end
      end
    end
  end
end
