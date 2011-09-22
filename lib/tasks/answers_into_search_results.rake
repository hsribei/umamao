require 'uri'
require 'cgi'

namespace :data do
  namespace :migrate do
    desc 'Creates SearchResult objects from Answer objects'
    task :answers_into_search_results => :environment do
      include ApplicationHelper

      answer_url = lambda do |params|
        URI::HTTP.build(:host => AppConfig.domain,
                        :port => AppConfig.port == 80 ? nil: AppConfig.port,
                        :path => "/questions/" <<
                                   "#{CGI.escape(params[:question_slug])}" <<
                                   "/answers/#{params[:answer_id]}")
      end

      Answer.find_each(:batch_size => 100, :fields => [:id,
                                                       :title,
                                                       :body,
                                                       :user_ip,
                                                       :user_id,
                                                       :group_id,
                                                       :question_id]) do |answer|
        begin
          question = Question.where(:id => answer.question_id).fields(:slug).first
          search_result =
            SearchResult.create!(:url => answer_url.
                                           call(:question_slug => question.slug,
                                                :answer_id => answer.id),
                                 :title => answer.title,
                                 :summary => truncate_words(answer.body),
                                 :user_id => answer.user_id,
                                 :group_id => answer.group_id,
                                 :question_id => answer.question_id)
          Vote.
            where(:voteable_id => answer.id, :voteable_type => 'Answer').
            fields([:group_id,
                    :imported_from_se,
                    :se_id,
                    :se_site,
                    :user_id,
                    :user_ip,
                    :value,
                    :voteable_id,
                    :voteable_type]).
            all.
            each do |vote|
            Vote.create!(:group_id => vote.group_id,
                         :imported_from_se => vote.imported_from_se,
                         :se_id => vote.se_id,
                         :se_site => vote.se_site,
                         :user_id => vote.user_id,
                         :user_ip => vote.user_ip,
                         :value => vote.value,
                         :voteable_id => search_result.id,
                         :voteable_type => search_result.class.to_s)
          end
        rescue StandardError
          STDERR.puts $!
        end
      end
    end
  end
end
