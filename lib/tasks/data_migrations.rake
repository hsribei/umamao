# -*- coding: utf-8 -*-
require 'mechanize'
require 'rubygems'
require 'lib/freebase'
require 'lib/wikipedia_parser'
require 'lib/wikipedia_fillin'

namespace :data do
  namespace :migrate do
    desc "Associate waiting users with existing users."
    task :associate_waiting_users => :environment do
      WaitingUser.find_each do |waiting_user|
        if user = User.find_by_email(waiting_user.email)
          waiting_user.user = user
          waiting_user.save!
          puts "Created for user #{waiting_user.email}"
        elsif affiliation = Affiliation.find_by_email(waiting_user.email)
          waiting_user.user = affiliation.user
          waiting_user.save!
          puts "Created for affiliation #{waiting_user.email}"
        end
      end
    end

    desc "Fill created_at field for objects that don't have one."
    task :fill_created_at_fields => :environment do
      AnswerRequest.find_each(:created_at => nil) do |request|
        request.created_at = request.updated_at = Time.now
        request.save!
      end
      ExternalAccount.find_each(:created_at => nil) do |account|
        account.created_at = account.updated_at = Time.now
        account.save!
      end
      GroupInvitation.find_each(:created_at => nil) do |invitation|
        invitation.created_at = invitation.updated_at = Time.now
        invitation.save!
      end
      UserTopicInfo.find_each(:created_at => nil) do |info|
        info.created_at = info.updated_at = Time.now
        info.save!
      end
    end

    desc "Change the class of user external accounts"
    task :specialize_user_external_accounts => :environment do
      ExternalAccount.find_each do |ea|
        ExternalAccount.set(ea.id, :_type => "UserExternalAccount",
                            :user_id => ea.user_id.to_s)
      end
    end

    desc "Calculate UserTopicInfo's votes balance"
    task :calculate_user_topic_info_votes_balance => :environment do
      UserTopicInfo.reset_votes_balance!
      UserTopicInfo.reset_answers_count!

      Answer.find_each do |answer|
        UserTopicInfo.answer_added!(answer)
        UserTopicInfo.update_vote_balance!(answer)
      end
    end

    desc "Generate notifications of accepted user suggestions"
    task :generate_accepted_user_suggestions_notifications => :environment do
      UserSuggestion.all(:accepted_at.ne => nil).each do |us|
        us.send_accept_notification_to_origin
      end
    end

    desc "Denormalize Invitation/Student relation."
    task :associate_students_to_invitations => :environment do
      Student.find_each do |student|
        if student.check_whether_has_been_invited
          student.has_been_invited = true
          student.save!
        end
      end
    end

    desc "Denormalize User/Student association."
    task :associate_students_to_users => :environment do
      Affiliation.find_each(:student_id.ne => nil) do |affiliation|
        affiliation.student.user = affiliation.user
        affiliation.student.save!
      end
    end

    desc "Set Unicamp email_code_regexp field"
    task :unicamp_email_code_regexp => :environment do
      unicamp = University.find_by_title "Unicamp"
      unicamp.email_code_regexp = '^[^@]*(\d{6})[^@]*@'
      unicamp.save!
    end

    desc "Recreate follow notifications."
    task :recreate_follow_notifications => :environment do
      User.find_each do |user|
        user.followers.each do |follower|
          options = {
            :event_type => "follow",
            :user_id => user.id,
            :origin_id => follower.id,
          }

          if Notification.first(options).blank?
            options[:created_at] =
              if user.created_at < follower.created_at
                follower.created_at
              else
                user.created_at
              end
            Notification.create!(options)
          end
        end
      end
    end

    desc "Remove notifications without questions"
    task :remove_notifications_without_questions => :environment do
      # Right now, notifications without questions should be destroyed.
      Notification.find_each do |n|
        if n.question.blank?
          puts "#{n.id} -> #{n.user.email}"
          n.destroy
        end
      end
    end

    desc "Recalculate questions count in search index."
    task :recalculate_questions_count_index => :environment do
      # Ignore topics that don't have questions. This is not correct,
      # but ought to work now.
      Topic.find_each(:questions_count.gt => 0) do |topic|
        topic.update_search_index true
      end
    end

    desc "Import CACo's exams as lists of questions"
    task :import_caco_exams => :environment do
      unicamp = University.find_by_short_name("Unicamp")

      # Map each file's name to the information extracted from it
      file_map = {}

      file_count = 0
      uploaded_count = 0

      # Iterate on each course group (e.g. MA, MC, etc)
      Dir[Rails.root.join("banco-de-provas", "{?,??}")].each do |code|

        # Iterate on each course
        Dir[code + "/*"].each do |course_code|
          course = Course.first(:code => File.basename(course_code).upcase,
                                :university_id => unicamp.id)
          if !course
            puts "Creating course #{File.basename(course_code).upcase}"
            # We put any name if the course doesn't exist
            code_upcase = File.basename(course_code).upcase
            course =
              Course.create!(:code => code_upcase, :name => code_upcase,
                             :title => "#{code_upcase} (Unicamp)",
                             :university_id => unicamp.id)
          end

          if course.present?
            # In a course's directory we can find professor subdir's or
            # standalone exams.
            Dir[course_code + "/*"].each do |entry|

              # Professor subdir
              if File.directory? entry
                Dir[entry + "/*"].each do |professor_entry|
                  re = /^.{4,5}-(.*)-(\d{4}s\d[^-]*)(-.+)?\.pdf$/
                  re_alt = /^.{4,5}-(.*)-[^-]+\.pdf$/
                  match = File.basename(professor_entry).match re
                  info = {}
                  if match
                    file_count += 1
                    info[:kind] =
                      case match[1]
                      when /p(\d+)/
                        "Prova #{$1}"
                      when /t(\d+)/
                        "Teste #{$1}"
                      when "ex"
                        "Exame"
                      when "2c"
                        "Segunda chamada"
                      else
                        "Prova #{match[1]}"
                      end
                    info[:period] = match[2]
                    info[:other] = match[3]
                  elsif File.basename(professor_entry).match re_alt
                    file_count += 1
                    info[:kind] = $1.tr("-", " ")
                  else
                    info[:kind] = :bogus
                    puts "Bogus #{professor_entry}"
                  end
                  info[:course] = course
                  file_map[professor_entry] = info
                end

              # Standalone exam.
              elsif entry =~ /\.pdf$/
                re = /^.{4,5}-(.*)-(\d{4}s\d[^-]*)(-.*)?\.pdf$/
                re_alt = /^.{4,5}-(.*)\.pdf$/
                match = File.basename(entry).match re
                info = {}
                if match
                  file_count += 1
                  info[:kind] =
                    case match[1]
                    when /p(\d+)/
                      "Prova #{$1}"
                    when /t(\d+)/
                      "Teste #{$1}"
                    when "ex"
                      "Exame"
                    when "2c"
                      "Segunda chamada"
                    else
                      match[1]
                    end
                  info[:period] = match[2]
                  info[:other] = match[3]
                elsif File.basename(entry).match re_alt
                  file_count += 1
                  info[:kind] = $1.tr("-", " ")
                else
                  info[:kind] = :bogus
                  puts "Bogus #{entry}"
                end
                info[:course] = course
                file_map[entry] = info
              else
                puts "  Unknown #{File.basename entry}"
              end
            end
          else
            puts "Missing #{course_code}"
          end
        end
      end

      inverse_map = {}

      file_map.each do |file, info|
        if info[:kind] == :bogus
          question_list_name = "Bogus"
        else
          question_list_name = ""
          question_list_name += info[:course].title if info[:course]
          question_list_name += " - #{info[:kind]}" if info[:kind]
          if info[:period].present?
            info[:period].match(/(\d{4})s(.)(.*)/)
            question_list_name += " - #{$2}s#{$1}#{$3}"
          end
        end

        inverse_map[question_list_name] ||= {
          :files => [],
          :course => info[:course]
        }
        inverse_map[question_list_name][:files] << file
      end

      base = Topic.find_by_title("Banco de provas")
      if !base
        base = Topic.create!(:title => "Banco de provas")
      end

      exercises_id = BSON::ObjectId("4cbefdbb79de4f58ea00012c")

      inverse_map.each do |name, info|
        list = QuestionList.find_by_title(name)
        if list
          puts "Found list #{name}"
        else
          puts "Creating list #{name}"
          topic_ids = [info[:course].id, base.id, exercises_id]
          list =
            QuestionList.create!(:title => String.new(name),
                                 :description => "",
                                 :main_topic_id => info[:course].id,
                                 :topic_ids => topic_ids)
        end

        if info[:files] != :bogus
          info[:files].each do |file_name|
            QuestionListFile.create!(:file => File.open(file_name),
                                     :question_list => list)
            puts "  Uploaded file #{File.basename file_name}"
          end
        end
      end
    end

    desc "Initialize news_item's visibility flag"
    task :initialize_news_items_visibility_flag => :environment do
      NewsItem.find_each do |ni|
        if ni.news_update_entry_type == "Question" and
          ni.news_update.entry.answers_count > 0
          ni.hide!
        else
          ni.show!
        end
      end
    end

    desc "Give three initial invites to everyone"
    task :give_first_invites => :environment do
      User.find_each do |user|
        user.invitations_left = 3
        user.save!
      end
    end
    desc "Randomly reset passwords for users that don't have one"
    task :fill_in_missing_passwords => :environment do
      total = 0
      User.find_each do |user|
        if user.encrypted_password.blank?
          new_password = ActiveSupport::SecureRandom.hex(8)
          user.reset_password!(new_password, new_password)
          total += 1
        end
      end
      puts total
    end

    desc "Remove notifications that reference objects that doesn't exist anymore"
    task :remove_orphaned_notifications => :environment do
      Notification.query.each do |notification|
        if !notification.origin ||
            notification.reason_id.present? && !notification.reason
          notification.destroy
          puts "Destroyed #{notification.id}"
        end
      end
    end

    desc "Change every inheriting class' news items to Topic"
    task :fix_news_items_types => :environment do
      NewsItem.query(:recipient_type.nin => ["Topic", "User"]).each do |ni|
        if ni.recipient_type.constantize < Topic
          ni.recipient_type = "Topic"
          ni.save!
        end
      end

      NewsItem.query(:origin_type.nin => ["Topic", "User"]).each do |ni|
        if ni.origin_type.constantize < Topic
          ni.origin_type = "Topic"
          ni.save!
        end
      end
    end

    # The next two tasks do the same thing; the second one should be used
    # while it's faster
    desc "Recalculate Topic's questions_count"
    task :recalculate_questions_count => :environment do
      Topic.find_each do |topic|
        old_questions_count = topic.questions_count
        topic.questions_count = Question.query(:topic_ids => topic.id).count
        topic.save if topic.questions_count != old_questions_count
      end
    end

    # This task should be faster when you've got a large ammount of Topics
    # (that fits on memory) and not so many questions
    desc "Recalculate Topic's questions_count"
    task :fast_recalculate_questions_count => :environment do
      topic_questions_count = Hash.new(0)

      Question.find_each do |q|
        q.topic_ids.each do |t_id|
          topic_questions_count[t_id] += 1
        end
      end

      Topic.find_each do |topic|
        old_questions_count = topic.questions_count
        topic.questions_count = topic_questions_count[topic.id]
        if topic.questions_count != old_questions_count && topic.save
          topic.update_search_index true
        end
      end
    end

    desc "Recalculate Topic's followers_count"
    task :recalculate_followers_count => :environment do
      Topic.find_each do |topic|
        topic.followers_count = topic.follower_ids.size
        topic.save
      end
    end

    desc "Fully migrate question versions"
    task :migrate_question_versions do
      Rake::Task["data:migrate:replace_topics_in_versions"].invoke
      Rake::Task["data:migrate:migrate_tags_in_versions"].invoke
    end

    desc "Convert :tags in old versions to topics"
    task :migrate_tags_in_versions => :environment do

      # Look for all tags occuring in versions
      versions_count = 0
      found_tags = Set.new
      Question.query.each do |question|
        question.versions.each do |version|
          if version.data[:tags].present?
            found_tags += version.data[:tags].map(&:strip)
            versions_count += 1
          end
        end
      end
      puts "Found #{versions_count} versions with tag content"

      # Look for an equivalent topic for each tag
      tag_mapping = {}
      look_later = {}
      found_tags.each do |tag|
        if tag == "c"
          # Hacky, but necessary
          new_tag = "C (Linguagem de programação)"
        else
          new_tag = tag
        end
        new_tag = new_tag.gsub(/(\w)-(\w)/, '\\1 \\2')
        new_tag = new_tag.gsub(/(\w)(cao)\b/, '\\1ção')
        new_tag_re = /^#{Regexp.escape new_tag}/i
        topics = Topic.query(:title.in => [new_tag_re]).all
        if topics.present?
          tag_mapping[tag] = topics.first.id
        else
          look_later[tag] = new_tag_re
        end
      end

      puts "Look harder..."
      # Tags we haven't found should be looked ignoring accents
      Topic.query.each do |topic|
        no_accents = topic.title.strip_accents
        look_later.each do |tag, re|
          if no_accents =~ re
            tag_mapping[tag] = topic.id
          end
        end
      end

      puts "Rebuilding versions..."
      Question.query.each do |question|
        changed = false
        question.versions.each do |version|
          if version.data[:tags].present?
            changed = true
            version.data[:topic_ids] =
              version.data[:tags].map{ |tag| tag_mapping[tag] }.compact
            version.data.delete :tags
          end
        end
        if changed
          question.save!
        end
      end
    end

    desc "Replace :topics by :topic_ids in question versions"
    task :replace_topics_in_versions => :environment do
      Question.query.each do |question|
        question.versions.each do |version|
          version.data.delete :topics
          version.data[:topic_ids] = []
        end
        question.save!
      end
    end

    desc "Remove erroneously added topics from Wikipedia articles"
    task :remove_non_global_wikipedia_articles => :environment do
      Topic.find_each(:created_at.gt => (Time.now - 12.hour), :followers_count => 0, :questions_count => 0) do |t|
        t.destroy
      end
    end

    desc "Create notifications for old events"
    task :create_old_notifications => :environment do

      # Notify old answers
      puts "Notifying answers"
      Answer.query.each do |answer|
        User.query(:id.in => answer.question.watchers).each do |watcher|
          next if watcher == answer.user ||
            Notification.first(:user_id => watcher.id,
                               :reason_id => answer.id,
                               :reason_type => "Answer")
          Notification.create!(:user => watcher,
                               :event_type => "new_answer",
                               :origin => answer.user,
                               :reason => answer,
                               :created_at => answer.created_at)

        end
      end

      # Notify old comments
      puts "Notifying comments"
      Comment.query(:_type.ne => "Answer").each do |comment|
        comment.users_to_notify.each do |recipient|
          next if Notification.first(:user_id => recipient.id,
                                     :reason_id => comment.id,
                                     :reason_type => "Comment")
          Notification.create!(:user => recipient,
                               :event_type => "new_comment",
                               :origin => comment.user,
                               :reason => comment,
                               :created_at => comment.created_at)
        end
      end

      # Notify old followers
      puts "Notifying old followers"
      User.query.each do |user|
        user.followers.each do |follower|
          next if Notification.first(:user_id => user.id,
                                     :origin_id => follower.id,
                                     :event_type => "follow")
          Notification.create!(:user => user,
                               :event_type => "follow",
                               :origin => follower,
                               :created_at => follower.created_at)
        end

        user.last_read_notifications_at = Time.now
        user.save :validate => false
      end
    end

    desc "Create a DJ to import Wikipedia"
    task :launch_wp => :environment do
      Rails.logger.info "Trying to launch"
      Rake::Task["data:migrate:do_launch_wp"].delay.invoke
    end

    desc "Actually execute the Wikipedia import"
    task :do_launch_wp => :environment do
      Rails.logger.info "Downloading Wikipedia"
      Rake::Task["data:migrate:download_wikipedia_articles"].invoke
      Rails.logger.info "Exporting Wikipedia"
      Rake::Task["data:migrate:import_wikipedia_articles"].invoke
    end

    desc "Add max_votes, min_votes and is_open fields to Questions"
    task :add_votes_and_is_open_to_questions => :environment do
      Question.query.each do |q|
        q.max_votes, q.min_votes = 0, 0
        q.is_open = true

        q.answers.each do |a|
          v = a.votes_count
          q.max_votes = v if v > q.max_votes
          q.min_votes = v if v < q.min_votes

          if q.max_votes > 0
            q.is_open = false
            q.news_update.on_question_status_change false
          else
            q.news_update.on_question_status_change true
          end
        end

        q.save
      end
    end

    desc "Download Freebase simple topic dump"
    task :download_freebase_topics do
      Freebase.download_simple_topic_dump
    end

    desc "Download Wikipedia article dump"
    task :download_wikipedia_articles do
      Wikipedia.download_wikipedia_articles_dump
    end

    desc "Import Wikipedia articles as topics"
    task :import_wikipedia_articles => :environment do
      # Add new topics 'off the record' for search
      # Do not add new topics to the search index
      Support::Search.disable
      parser = Nokogiri::XML::SAX::Parser.new(WikipediaPagesArticleDumpParser.new)
      parser.parse(File.open("#{Wikipedia::DOWNLOAD_DIRECTORY}#{Wikipedia::ARTICLES_XML}"))
      Support::Search.enable

      # Regenerate search index, as it isn't up-to-date
      Rake::Task["search:reset"].invoke
    end

    desc "Import Freebase information for each topic"
    task :import_freebase_content => :environment do
      n_topics = Topic.count

      reqs = [n_topics.to_f/Freebase::DAILY_MAX_REQS, Freebase::MIN_REQS].max

      paginate_opts = {
        :per_page => reqs,
        :wikipedia_import_status => Wikipedia::ImportStatus::OK
      }

      paginated_topics = Topic.paginate(paginate_opts)

      while paginated_topics.any?
        FreebaseImporter.fillin_topics(paginated_topics)
        break if paginated_topics.next_page.nil?
        paginated_topics =
          Topic.paginate(paginate_opts.merge(:page => paginated_topics.next_page))
      end
    end

    desc "Import Wikipedia description for each topic"
    task :import_wikipedia_description => :environment do
      query_opts = {
        :wikipedia_import_status => Wikipedia::ImportStatus::OK,
        :wikipedia_description_imported_at => nil
      }
      Topic.find_each(query_opts) do |topic|
        WikipediaImporter.fillin_topic topic
      end
    end

    desc "Extract mid's from Freebase simple topic dump"
    task :extract_freebase_mids do
      Freebase.extract_mids_file_from_simple_topic_dump
    end

    desc "Remove \"empty\" Questions"
    task :remove_empty_questions => :environment do
      Question.query.each do |q|
        q.destroy if q.title.nil?
      end
    end

    desc "Regenerate Questions NewsItems"
    task :regenerate_questions_news_items => :environment do
      Question.query.each do |q|
        nu = q.news_update

        if nu != nil and nu.entry_type == "Question"
          if nu.news_items.nil?
            NewsItem.from_news_update! nu
          else
            nu.news_items.each do |ni|
              ni.open_question = nu.entry.is_open
              ni.news_update_entry_type = "Question"
              ni.save
            end
          end
        end

      end
    end

    desc "Recalculate votes average"
    task :recalculate_votes_average => :environment do
      Comment.query.each do |voteable|
        score = 0
        voteable.votes.each do |v|
          score += v.value
        end
        voteable.votes_count = voteable.votes.count
        voteable.votes_average = score
        voteable.save :validate => false
      end
    end

    desc "Add default topics to each university"
    task :add_default_topics_to_universities => :environment do

      # Topics of interest to everyone
      shared_topics = []
      ["Moradia", "Bolsas",
       "Consumo consciente",
       "Iniciação científica", "Intercâmbio",
       "Assistência estudantil", "Entrega em domicílio",
       "Esporte", "Aprendizado de idiomas", "Aluguel",
       "Bicicleta"].each do |title|
        topic = Topic.find_by_title(title)
        if topic.blank?
          puts "Topic \"#{title}\" not found!"
        else
          shared_topics << topic
        end
      end

      University.query.each do |university|
        name = university.short_name || university.name
        if university.university_topics.blank?
          puts "Populating topics for #{name}"
          own_topic = Topic.find_by_title(name)
          if own_topic.blank?
            puts "Creating topic \"#{name}\""
            own_topic = Topic.create!(:title => name)
          end

          university.university_topics << own_topic
          shared_topics.each do |topic|
            university.university_topics << topic
          end
          university.save :validate => false
        else
          puts "Skipping #{name}"
        end
      end
    end

    desc "Add the user's university to his short bio"
    task :add_university_to_short_bio => :environment do
      User.query.each do |user|
        if user.bio.blank? && user.affiliations.present?
          university = user.affiliations.first.university
          puts ("Populating short bio for user \"#{user.name}\" " +
                "from #{university.short_name}")
          user.bio = university.short_name
          user.save :validate => false
        else
          puts "Skipping user \"#{user.name}\""
        end
      end
    end

    desc "Add question authors as watchers"
    task :add_question_authors_as_watchers => :environment do
      Question.query.each do |question|
        if question.user_id.blank?
          puts "Missing author in \"#{question.title}\""
          next
        elsif !question.watchers.include?(question.user_id)
          puts "Added user \"#{question.user.name}\" in \"#{question.title}\""
          question.add_watcher(question.user)
        else
          puts "Skipped \"#{question.title}\""
        end
      end
    end

    desc "Find topics related to Unicamp."
    task :populate_unicamp_topics => :environment do
      unicamp = University.find_by_short_name("Unicamp")
      topic_names = ["Unicamp",
                     "Barão Geraldo", "Campinas",
                     "DAC (Unicamp)", "SAE Unicamp",
                     "CECOM (Unicamp)",
                     "Restaurante Universitário da Unicamp (Bandejão)",
                     "Bolsas-auxílio (Unicamp)",
                     "Comida na Unicamp", "Moradia Estudantil da Unicamp",
                     "DCE da Unicamp", "Sistema de Bibliotecas da Unicamp",
                     "Restaurantes da Unicamp", "Intercâmbio"]
      topic_names.each do |topic_name|
        puts topic_name
        topic = Topic.find_by_title(topic_name)
        if topic.blank?
          puts "Could not find topic \"#{topic_name}\""
        else
          unicamp.university_topics << topic
        end
      end
      unicamp.save!
    end

    desc "Calculate each topic's followers count"
    task :calculate_followers_count => :environment do
      Topic.query.each do |topic|
        next if topic.follower_ids.blank?
        topic.followers_count = topic.follower_ids.length
        topic.save :validate => false
      end
    end

    desc "Create suggestion lists for all users."
    task :create_suggestion_lists => :environment do
      User.query.each do |user|
        if user.suggestion_list.blank?
          puts user.name
          user.suggestion_list = SuggestionList.new(:user => user)
          user.save :validate => false
        else
          puts "User #{user.name} had already a suggestion list"
        end
      end
    end

    desc "Delete a question's news items if it has already been answered."
    task :delete_duplicate_news_items => :environment do
      Question.query.each do |question|
        if !question.answers.blank? && question.news_update
          NewsItem.query(:news_update_id => question.news_update.id).each do |item|
            item.destroy
          end
        end
      end
    end

    desc "Create missing news items for topics."
    task :create_news_items_for_topics => :environment do
      Question.query.each do |question|
        next if !question.news_update

        question.topics.each do |topic|
          if NewsItem.query(:recipient_id => topic.id,
                            :recipient_type => "Topic",
                            :news_update_id => question.news_update.id).count == 0
            NewsItem.notify!(question.news_update, topic, topic, question.news_update.created_at)
          end

          question.answers.each do |answer|
            next if !answer.news_update # This shouldn't happen.
            if NewsItem.query(:recipient_id => topic.id,
                              :recipient_type => "Topic",
                              :news_update_id => answer.news_update.id).count == 0
              NewsItem.notify!(answer.news_update, topic, topic, answer.news_update.created_at)
            end
          end
        end
      end
    end

    desc "Update old users format (academic e-mail inside users model) to the new one (user affiliation university)"
    task :move_user_academic_email_to_affiliation => :environment do

      unconfirmed_users = 0

      User.where(:academic_email.ne => nil).each do |user|
        if Affiliation.find_by_email(user.academic_email).present?
          puts "Skipping email #{user.academic_email}"
          next
        end
        puts "Creating affiliation for #{user.academic_email}"
        a = Affiliation.new
        a.user = user
        unconfirmed = false

        if !(a.confirmed_at = user.confirmed_at)
          puts "Unconfirmed affiliation for #{user.academic_email}"
          unconfirmed = true

          # HACK: We do not want to send emails to old unconfirmed
          # users.  The confirmation step is ignored if the
          # affiliation has a confimation date, so we set it now and
          # unset it later.
          a.confirmed_at = Time.now
          unconfirmed_users += 1
        end

        a.email = user.academic_email
        short_name = /[.@]unicamp.br$/ =~ a.email ? "Unicamp" : "USP"
        a.university = University.where(:short_name => short_name).first

        a.save!
        if unconfirmed
          # This will avoid the after_create hook.
          a.confirmed_at = nil
          a.save!
        end

        user.save :validate => false
      end

      puts "There were #{unconfirmed_users} unconfirmed users"
    end

    desc "(USING THIS WILL REMOVE DOMAINS!) fix csv file from uni2.csv to uni.csv"
    task :fix_csv_file => :environment do
      require 'ccsv'
      f = File.new("data/uni.csv", "w")
      Ccsv.foreach("data/uni2.csv") do |row|
        name      = row[0].split('-')[0].tr("\"", "")

        short_name   = row[1].tr("\"", "")
        state     = row[2].tr("\"", "")

        if row[3] == "TRUE" then
          open_for_signup = "TRUE"
        else
          open_for_signup = "FALSE"
        end
        f.puts("\"#{name}\", \"#{short_name}\", \"#{state}\", \"#{open_for_signup}\", \"\"")
      end
      f.close
    end

    desc "Import Universities from a csv file in the format [name, short_name,
 state, V, domain] where V is TRUE if the university is open for signup or
 FALSE otherwise"
    task :import_universities => :environment do
      require 'ccsv'
      Ccsv.foreach("data/uni.csv") do |row|
        a = University.new
        a.name = row[0].split('-')[0].tr("\"", "")
        a.name.downcase_with_accents!
        a.name = a.name.phrase_ucfirst.strip

        a.short_name = row[1].tr("\"", "").strip
        a.state = row[2].tr("\"", "").strip

        a.open_for_signup = (row[3].tr("\"", "").strip == "TRUE")
        a.validation_type = "email"
        a.domains = row[4].tr("\"", "").strip.split(" ")
        a.save!
        nil
      end
    end

    desc "Create news updates for entries that don't have one"
    task :create_old_news_updates => :environment do
      Question.query.each do |question|
        if !question.news_update
          question.create_news_update
        end
      end

      Answer.query.each do |answer|
        if !answer.news_update
          answer.create_news_update
        end
      end
    end

    desc "Update questions count in topics"
    task :update_topic_questions_count => :environment do
      Topic.query.each do |topic|
        topic.questions_count = Question.query(:topic_ids => topic.id,
                                               :banned => false).count
        topic.save
      end
    end

    desc "Remove duplicate votes"
    task :remove_dup_votes => :environment do
      dups = Vote.all.group_by{|v| [v.user_id, v.voteable_id, v.voteable_type]}.
        to_a.each{|g| g[1][1..-1].map {|v| v.destroy}}

      if Vote.all.group_by{|v| [v.user_id, v.voteable_id, v.voteable_type]}.
          to_a.select{|g| g[1].length > 1}.length == 0
        puts "Success!"
      else
        puts "Error"
      end
    end

    desc "Move tags from an array of strings into their own (Topic) model"
    task :tags_to_topics => :environment do
      Topic.delete_all

      questions = Question.query
      questions.each do |question|
        topics = question.tags.map { |tag|
          topic = Topic.find_by_title(tag)

          if !topic
            topic = Topic.create(:title => tag)
            topic.set(:created_at => question.created_at)
          end

          topic.set(:questions_count => topic.questions_count + 1)
          topic
        }
        question.set(:topic_ids => topics.map(&:id).uniq)
      end

      # Text transformations on topics
      Topic.query.each do |topic|
        title = topic.title.split('-').map { |w|
          word = w[0..0].upcase + w[1..-1]
          word.gsub!(/cao$/, 'ção')
          word.gsub!(/ao$/, 'ão')
          word
        }.join(' ')

        if title =~ /^\w{1,2}\d{3}$/
          title = title.upcase + ' (Unicamp)'
        end

        topic.set(:title => title)
        # we want the slug to be generated from the new title
        topic.reload
        topic.send(:generate_slug)
        topic.set(:slug => topic.slug)
      end
    end

    desc "Rebuild filter indexes for questions, users and topics"
    task :rebuild_indexes => :environment do
      Question.all.each {|q| q.save :validate => false}
      Topic.all.each {|q| q.save :validate => false}
      User.all.each {|q| q.save :validate => false}
    end

    desc "Migrate news items to polymorphic version"
    task :remake_news_items => :environment do
      NewsItem.all.each {|i| i.recipient_type = "User"; i.save}
    end

    desc 'Import courses from Unicamp into topics'
    task :import_unicamp_courses => :environment do
      agent = Mechanize.new
      pagelist = agent.get('http://www.dac.unicamp.br/sistemas/catalogos/grad/catalogo2010/ementas/')

      pagelist.links.select{|l| l.href.include?('todas')}.each do |link|
        courses = []
        course = {}
        link.click

        # the first 4 items are just page header information
        text_items = agent.page.search('font[size="-1"]').map{|el| el.text.strip}[4..-1]

        text_items.each do |item|
          case item
          when /^(\w+\d+) (.*)/ # e.g.: AD012 Ateliê de Prática em Dança II
            if course.present?
              courses << course
              print '-' # progress indicator
              course = {}
            end

            course[:code] = $1
            course[:title] = $2

          when /^Pré-Req\.: (.*)/ # e.g.: Pré-Req.: AD011 F 429
            course[:pre_reqs] = $1.scan(/([A-Za-z]+\d+)|([fF] \d+)/).flatten.compact

          when /^Ementa: (.*)/
            course[:syllabus] = $1.strip
          end
        end

        courses << course
        print '-' # progress indicator

        courses.each do |course|
          topic = Topic.find_or_create_by_title("#{course[:code]} (Unicamp)")

          pre_req_links = course[:pre_reqs].present? ?
          "<strong>Pré-requisitos</strong>: " + course[:pre_reqs].map { |code|
            "<a href=\"/topics/#{code.tr(' ', '-')}-Unicamp\">#{code}</a>"
          }.join(', ') + "\n\n" : ''


          topic.description = "# #{course[:code]}: #{course[:title]}\n\n"
          topic.description << pre_req_links + (course[:syllabus] || '')
          topic.save
          print '.' # progress indicator
        end

        sleep 1
      end

    end

    desc 'Remove html code from Topic\'s description'
    task :remove_html_code_topic_description => :environment do
      Topic.all(:description => {"$ne" => nil}).each do |t|
        if t.description.present?
          t.description.gsub!(/<strong>([^<]*)<\/strong>/, '**\1**')

          t.description.gsub!(/<code>([^<]*)<\/code>/, '`\1`')

          if /<a/ =~ t.description
            # Find the greatest index for link
            max = 0
            t.description.scan(/\[(\d*)\]: .*/).each do |number|
              if number.to_i > max
                max = number.to_i
              end
            end

            # Change the anchor to markdown format
            new_links = ""
            t.description.scan(/<a href="([^"]*)">([^<]*)<\/a>/).each do |link|
              max = max + 1
              t.description.gsub!("<a href=\"#{link[0]}\">#{link[1]}</a>", "[#{link[1]}][#{max}]")
              new_links += "\n  [#{max}]: #{link[0]}"
            end
            t.description += new_links

          end

          t.save(:validate => false)
        end
      end
    end

    def get_university(old_university)
      if t = Topic.find_by_title(old_university["short_name"])
        Topic.set(t.id, :_type => "University")
        u = University.find_by_id(t.id)
      else
        u = University.new()
        u.title = old_university["short_name"]
      end
      old_university.delete "_id"
      u.update_attributes(old_university)
      u.save!
      u
    end

    desc "Make Universities be topics"
    task :make_university_as_topic => :environment do
      # Import Universities
      MongoMapper.database['universities'].find({}).to_a.each do |old_university|
        # Print a status information
        print '-'

        old_id = old_university["_id"]
        u = get_university(old_university)

        AcademicProgram.query(:university_id => old_id).each do |ap|
          ap.university_id = u.id
          ap.save(:validate => false)
        end

        Affiliation.query(:university_id => old_id).each do |a|
          a.university_id = u.id
          a.save(:validate => false)
        end

        Course.query(:university_id => old_id).each do |c|
          c.university_id = u.id
          c.save(:validate => false)
        end

        Student.query(:university_id => old_id).each do |s|
          s.university_id = u.id
          s.save(:validate => false)
        end

      end
      print "\n"
    end

    desc 'Convert last_logged_at attribute to last_sign_in_at'
    task :change_logged_track_attribute => :environment do
      User.all(:last_logged_at => {"$ne" => nil}).each do |u|
        u.last_sign_in_at = u.last_logged_at.utc
        u.save(:validate => false)
      end
    end

    desc "Create Academic Programs topics"
    task :create_academic_program_topics => :environment do

      AcademicProgram.all.each do |ap|
        name = ap.name.split("-")[0].strip
        print "-"
        if t = Topic.find_by_title(name)
          unless t.types.include? "AcademicProgram"
            t.types << "AcademicProgram"
            t.save
          end
        else
          t = Topic.create(:title => name, :types => "AcademicProgram")
        end
      end

      print "\n"
    end

    desc "Fix student names"
    task :fix_student_names => :environment do
      Student.all(:name => /^[^A-Za-z]/).each do |s|
        print "-"
        s.name = s.name.match(/[A-Za-z].*\w/)[0]
        s.save(:validate => false)
      end
      print "\n"
    end

    def create_user_topic_info(user_id, topic_id, opts = {})
      return if UserTopicInfo.count(:user_id => user_id,
                                    :topic_id => topic_id) > 0
      uti = UserTopicInfo.new(:user_id => user_id, :topic_id => topic_id)

      if opts[:following]
        uti.follow!
      end
      if opts[:ignoring]
        uti.ignore!
      end
      uti.save!
    end

    desc "Migrate topic's follower information to UserTopicInfo model"
    task :user_topic_info_migration => :environment do
      print "Followed\n"
      Topic.query(:follower_ids=> {"$not" => {'$size' => 0}}).each do |topic|
        if topic['follower_ids'].blank?
          puts topic['follower_ids']
        end
        next if topic['follower_ids'].blank?
        topic['follower_ids'].each do |user_id|
          next if UserTopicInfo.count(:user_id => user_id,
                              :topic_id => topic.id) > 0
          print "-"
          create_user_topic_info(user_id, topic.id, :following => true)
        end
      end
      print "\nIgnored\n"
      User.find_each(:ignored_topic_ids => {"$not" => {"$size" => 0}}) do |user|
        print "-"
        user['ignored_topic_ids'].each do |topic_id|
          create_user_topic_info(user.id, topic_id, :ignoring => true)
        end
      end
    end

    desc "Update UserTopicInfo counts"
    task :update_user_topic_info_counts => :environment do
      (Question.fields([:user_id]).query.map(&:user_id) | Answer.fields([:user_id]).query.map(&:user_id)).uniq.each do |user_id|
        UserTopicInfo.find_each(:user_id => user_id) do |uti|
          print "-"
          uti.update_counts
        end
      end
    end

    desc "Prune topics that don't have any questions or followers"
    task :prune_topics => :environment do
      prune_topic = lambda do |t|
        if t.questions.count.zero? && t.follower_ids.count.zero?
          begin
            t.delete
            print '.'
          rescue
            print 'E'
          end
        else
          print 'F'
        end
      end

      # Prune topics that have zero counts
      Topic.find_each(:questions_count => 0,
                      :followers_count => 0,
                      &prune_topic)
    end
  end
end
