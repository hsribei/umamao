# -*- coding: utf-8 -*-

namespace :news_items do
  desc "Remove duplicated news items."
  task :remove_duplicates => :environment do
    NewsItem.find_each(:batch_size => 10_000, :verified => nil) do |ni|
      print '_'
      ni.set(:verified => true)
      nis = NewsItem.where(:news_update_id => ni.news_update_id,
                           :recipient_id => ni.recipient_id)
      if nis.count > 1
        nis.all[1..-1].map do |n|
          print( n.destroy ? '.' : 'F')
        end
      end
    end
  end

  desc "Clear verified attribute on news items."
  task :clear_verified_attribute => :environment do
    NewsItem.unset({:verified.ne => nil}, :verified)
  end

  desc 'Fix hidden news items visibility'
  task :fix_hidden_visibility => :environment do
    # The number of users that ignore topics is very low
    # So this rake task first turn all news_items visible
    # and after that hide the news items that should be
    # hidden
    NewsItem.set({}, :visible => true)
    i = 0
    User.find_each do |u|
      print '.'
      if (ignored_topic_ids = u.ignored_topic_ids).present?
        NewsItem.find_each(:recipient_id => u.id) do |ni|
          i = i + 1
          ni.set(:visible => false) if ni.should_be_hidden?(ignored_topic_ids)
        end
      end
    end
    puts i
  end

  desc 'Update entry_activity_at field on news_items of question'
  task :update_entry_activity_at => :environment do
    activity_at_hash = {}
    NewsUpdate.find_each(:entry_type => "Question") do |nu|
      activity_at_hash[nu.id] = nu.entry.activity_at
    end
    NewsItem.find_each(:batch_size => 1_000,
                       :entry_activity_at => nil,
                       :news_update_entry_type => "Question") do |ni|
      print '.'
      ni.set(:entry_activity_at => activity_at_hash[ni.news_update_id])
    end
    print "\nTotal news items of questions without entry_activity_at: "
    puts NewsItem.count(:news_update_entry_type => 'Question',
                        :entry_activity_at => nil)
  end
end
