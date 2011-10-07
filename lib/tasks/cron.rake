task :cron => :environment do
  Rake::Task["cron_tasks:refresh_related_topics"].execute
  Rake::Task["suggestions:refresh"].execute
  Rake::Task["cron_tasks:send_survey_to_newcomers"].execute
end

namespace :cron_tasks do
  desc "Refreshes each topic's list of related topics"
  task :refresh_related_topics => :environment do
    Rails.logger.info "Refreshing list of related topics..."
    Topic.find_each do |topic|
      next if topic.questions_count == 0
      topic.find_related_topics
      topic.save :validate => false
    end
  end

  task :send_survey_to_newcomers => :environment do
    User.find_each(:created_at => { :$gte => 8.days.ago.midnight,
                                    :$lt => 7.day.ago.midnight },
                   :batch_size => 10) do |user|
      Notifier.delay.survey(user)
    end
  end
end
