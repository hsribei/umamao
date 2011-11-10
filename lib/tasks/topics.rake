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
end
