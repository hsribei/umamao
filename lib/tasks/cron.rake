task :cron => :environment do
  Rake::Task["cron_tasks:send_survey_to_newcomers"].execute
  Rake::Task["cron_tasks:refresh_related_topics"].execute
end

namespace :cron_tasks do
  desc "Refreshes each topic's list of related topics"
  task :refresh_related_topics => :environment do
    Rake::Task["data:migrate:regenerate_related_topics"].execute
  end

  task :send_survey_to_newcomers => :environment do
    User.find_each(:created_at => { :$gte => 8.days.ago.midnight,
                                    :$lt => 7.days.ago.midnight },
                   :batch_size => 10) do |user|
      unless SentSurveyMail.first(:user_id => user.id)
        Notifier.delay.survey(user)
      end
    end
  end
end
