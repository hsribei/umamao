namespace :search_results do
  desc "Recalculate votes balance (aka \"average\")"
  task :recalculate_votes_balance => :environment do
    SearchResult.find_each(:batch_size => 10_000) do |sr|
      votes_balance = sr.votes.map(&:value).reduce(0,&:+)
      if votes_balance != sr.votes_average
        sr.set(:votes_average => votes_balance)
        print 'C'
      else
        print '.'
      end
    end
  end

  desc "Recalculate votes count"
  task :recalculate_votes_count => :environment do
    SearchResult.find_each(:batch_size => 10_000) do |sr|
      votes_count = sr.votes.count
      if votes_count != sr.votes_count
        sr.set(:votes_count => votes_count)
        print 'C'
      else
        print '.'
      end
    end
  end

  desc "Refill titles"
  task :refill_titles => :environment do
    SearchResult.find_each(:batch_size => 10_000) do |sr|
      old_title = sr.title
      sr.send('fetch_response_body')
      sr.send('fill_title')
      if sr.title != old_title
        sr.set(:title => sr.title)
        print 'C'
      else
        print '.'
      end
    end
  end
end
