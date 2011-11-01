# -*- coding: utf-8 -*-

namespace :news_items do
  desc "Remove duplicated news items."
  task :remove_duplicates => :environment do
    NewsItem.find_each(:batch_size => 10_000) do |ni|
      nis = NewsItem.where(:news_update_id => ni.news_update_id,
                           :recipient_id => ni.recipient_id)
      if nis.count > 1
        nis.all[1..-1].map do |n|
          print( n.destroy ? '.' : 'F')
        end
      end
    end
  end
end
