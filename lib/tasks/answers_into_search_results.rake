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
                                 :title => answer.title,
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
        #"votes_average" => 0,
            #"_keywords" => [[0] "2}",
                            #[1] "over",
                            #[2] "bla",
                            #[3] "x^2",
                            #[4] "sin",
                            #[5] "frac{",
                            #[6] "]",
                            #[7] "pi}{6}" #],
      #"version_message" => nil,
        #"updated_by_id" => nil,
          #"question_id" => "4c8906d579de4f1a200002b1",
              #"se_site" => "umamo",
           #"created_at" => Sat Dec 19 21:29:22 UTC 2009,
     #"imported_from_se" => true,
     #"commentable_type" => nil,
                 #"body" => "\n\n\\[ x^2 \\] bla bla \n\\[ \\sin \\frac{\\pi}{6} = {1 \\over 2}\\]\n\n\n\n",
       #"commentable_id" => nil,
           #"updated_at" => Fri Apr 08 21:09:44 UTC 2011,
          #"flags_count" => 0,
             #"language" => "pt-BR",
                  #"_id" => "4c8906d879de4f1a200002b2",
             #"group_id" => "4c8906ba79de4f1a1d000005",
                #"_type" => "Answer",
          #"votes_count" => 0,
    #"content_image_ids" => [],
              #"user_id" => "4c8906d179de4f1a20000009",
             #"versions" => [],
              #"user_ip" => nil,
                #"se_id" => "2",
          #"views_count" => "0",
                 #"wiki" => false,
               #"banned" => true
          Comment.
            where(:commentable_id => answer.id, :commentable_type => 'Answer').
            fields([:imported_from_se,
                    :se_id,
                    :se_site,
                    :user_id,
                    :user_ip,
                    :value,
                    :commentable_id,
                    :commentable_type]).
            all.
            each do |comment|
            Comment.create!(:group_id => GROUP.id,
                            :imported_from_se => comment.imported_from_se,
                            :se_id => comment.se_id,
                            :se_site => comment.se_site,
                            :user_id => comment.user_id,
                            :user_ip => comment.user_ip,
                            :value => comment.value,
                            :commentable_id => search_result.id,
                            :commentable_type => search_result.class.to_s)
          end
        rescue StandardError
          STDERR.puts $!
        end
      end
    end
  end
end
