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
end
