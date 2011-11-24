namespace :questions do
  desc 'Update activity_at field'
  task :update_activity_at => :environment do
    Question.find_each do |q|
      last_updated_at = q.search_results.map(&:created_at).max || q.created_at
      q.set(:activity_at => last_updated_at)
    end
  end
end
