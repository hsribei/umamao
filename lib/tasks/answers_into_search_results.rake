require 'uri'
require 'cgi'

namespace :data do
  namespace :migrate do
    desc 'Creates SearchResult objects from Answer objects'
    task :answers_into_search_results => :environment do
      raise 'You must have created a Group' unless Group.exists?

      include ApplicationHelper

      GROUP = Group.first

      answer_url = lambda do |params|
        URI::HTTP.build(:host => AppConfig.domain,
                        :port => AppConfig.port == 80 ? nil: AppConfig.port,
                        :path => "/questions/" <<
                                   "#{CGI.escape(params[:question_slug])}" <<
                                   "/answers/#{params[:answer_id]}")
      end

      optional = lambda do |object, message|
        object.respond_to?(message) ? object.send(message) : nil
      end

      Answer.find_each(:batch_size => 100, :fields => [:id,
                                                       :title,
                                                       :body,
                                                       :user_ip,
                                                       :user_id,
                                                       :question_id]) do |answer|
        begin
          question = Question.where(:id => answer.question_id).fields(:slug).first
          search_result =
            SearchResult.create!(:url => answer_url.
                                           call(:question_slug => question.slug,
                                                :answer_id => answer.id),
                                 :title => answer.title(:truncated => true),
                                 :summary => truncate_words(answer.body),
                                 :user_id => answer.user_id,
                                 :group_id => GROUP.id,
                                 :question_id => answer.question_id)
          Vote.
            where(:voteable_id => answer.id, :voteable_type => 'Answer').
            fields([:imported_from_se,
                    :se_id,
                    :se_site,
                    :user_id,
                    :user_ip,
                    :value,
                    :voteable_id,
                    :voteable_type]).
            all.
            each do |vote|
            Vote.create!(:group_id => GROUP.id,
                         :imported_from_se => vote.imported_from_se,
                         :se_id => vote.se_id,
                         :se_site => vote.se_site,
                         :user_id => vote.user_id,
                         :user_ip => vote.user_ip,
                         :value => vote.value,
                         :voteable_id => search_result.id,
                         :voteable_type => search_result.class.to_s)
          end

          Comment.
            where(:commentable_id => answer.id, :commentable_type => 'Answer').
            fields([:banned,
                    :body,
                    :content_image_ids,
                    :created_at,
                    :flags_count,
                    :imported_from_se,
                    :language,
                    :question_id,
                    :se_id,
                    :se_site,
                    :updated_at,
                    :updated_by_id,
                    :user_id,
                    :user_ip,
                    :versions,
                    :views_count,
                    :wiki,
                    :version_message]).
            all.
            each do |comment|
            Comment.create!(:banned => comment.banned,
                            :body => comment.body,
                            :commentable_id => search_result.id,
                            :commentable_type => search_result.class.to_s,
                            :content_image_ids =>
                              optional.call(comment, :content_image_ids),
                            :created_at => comment.created_at,
                            :flags_count =>
                              optional.call(comment, :flags_count),
                            :group_id => GROUP.id,
                            :imported_from_se => comment.imported_from_se,
                            :language => comment.language,
                            :question_id => comment.question_id,
                            :se_id => comment.se_id,
                            :se_site => comment.se_site,
                            :updated_at => comment.updated_at,
                            :updated_by_id =>
                              optional.call(comment, :updated_by_id),
                            :user_id => comment.user_id,
                            :user_ip => comment.user_ip,
                            :versions => optional.call(comment, :versions),
                            :views_count =>
                              optional.call(comment, :views_count),
                            :wiki => optional.call(comment, :wiki),
                            :version_message =>
                              optional.call(comment, :version_message))
          end
        rescue StandardError
          STDERR.puts $!
        end
      end
    end
  end
end
