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
end
