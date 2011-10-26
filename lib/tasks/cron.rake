task :cron => :environment do
  Rake::Task["cron_tasks:refresh_related_topics"].execute
end

namespace :cron_tasks do
  desc "Refreshes each topic's list of related topics"
  task :refresh_related_topics => :environment do
    Rake::Task["data:migrate:regenerate_related_topics"].execute
  end

  task :send_survey_to_newcomers => :environment do
    days_ago = 7.days.ago
    User.find_each(:created_at => { :$gte => (days_ago + 1).midnight,
                                    :$lt => days_ago.midnight },
                   :batch_size => 10) do |user|
      Notifier.delay.survey(user)
    end
  end
end
