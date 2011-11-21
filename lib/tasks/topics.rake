require 'language_detector'

LANG_PT_BR = 'pt'
BRAZIL_LOCALE = 'BR'

namespace :topics do
  desc 'Move questions from given topic to another localized topic'
  task :localize_questions, :topic_id, :needs => :environment do |t, args|
    detector = LanguageDetector.new

    orig = Topic.find_by_slug_or_id(args[:topic_id])
    local = Topic.find_or_create_by_title("#{orig.title}#{BRAZIL_LOCALE}")

    orig.questions.each do |q|
      corpus = "#{q.title} #{q.body} #{q.answers.map(&:body).join(" ")}"
      if detector.detect(corpus) == LANG_PT_BR
        q.pull(:topic_ids => orig.id)
        q.push(:topic_ids => local.id)
      end
    end
  end

  desc "Prune topics that don't have any questions or followers"
  task :prune => :environment do
    prune_topic = lambda do |t|
      if (questions_count = t.questions.count).zero? &&
        (topics_count = t.follower_ids.count).zero?
        print( t.delete ? '.' : 'E' )
      else
        print 'F'
        t.set(:questions_count => questions_count)
        t.set(:topics_count => topics_count)
      end
    end

    # Prune topics that have zero counts
    Topic.find_each(:questions_count => 0,
                    :followers_count => 0,
                    &prune_topic)
  end

  desc "Check and fix topics dependent content"
  task :check_and_fix_dependent_content => :environment do
    ['news_items', 'notifications', 'user_topic_info', 'question_versions'].
      each do |t|
        Rake::Task["topics:check_and_fix:#{t}"].invoke
      end
  end

  namespace :check_and_fix do
    def check_and_destroy_if(obj, &block)
      if yield(obj)
        print(obj.destroy ? 'D' : 'F')
      else
        print '.'
      end
    end

    desc "Check if there are broken news_items and remove the broken ones"
    task :news_items => :environment do
      NewsItem.find_each(:batch_size => 10_000) do |ni|
        check_and_destroy_if(ni) do
          ni.origin.nil? || ni.recipient.nil? || ni.news_update.nil?
        end
      end
    end

    desc "Check if there are broken notifications and remove the broken ones"
    task :notifications => :environment do
      Notification.find_each(:batch_size => 10_000) do |n|
        check_and_destroy_if(n) do
          n.origin.nil? || n.topic.nil?
        end
      end
    end

    desc "Check if there are broken user_topic_infos and remove the broken ones"
    task :user_topic_info => :environment do
      UserTopicInfo.find_each(:batch_size => 10_000) do |uti|
        check_and_destroy_if(uti) do
          uti.user.nil? || uti.topic.nil?
        end
      end
    end

    desc "Check if there are broken question_versions and remove the broken ones"
    task :question_versions => :environment do
      Question.find_each(:batch_size => 1_000) do |q|
        next if q.versions.blank?

        changed = false
        q.versions.each do |v|
          v.data[:topic_ids].each do |tid|
            unless Topic.find(tid)
              v.data[:topic_ids].delete(tid)
              changed = true
            end
          end
        end

        if changed
          print(q.save! ? 'C' : 'F')
        else
          print('.')
        end
      end
    end
  end
end
