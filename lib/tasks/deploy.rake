desc "Deploy app based on current master branch."
task :deploy do
  Rake::Task["deploy:update_production_branch"].invoke
  Rake::Task["deploy:push_production_branch"].invoke
end

namespace :deploy do

  task :environment do
    require 'grit'
    require 'yaml'
    Repo = Grit::Repo.new '.'

    CloudfilesConfig =
      YAML.load_file(Rails.root + "config/shapado.yml")[Rails.env]["rackspace"]["cloudfiles"]

    storage = Fog::Storage.new(
      :provider => 'Rackspace',
      :rackspace_username => CloudfilesConfig['username'],
      :rackspace_api_key => CloudfilesConfig['api_key']
    )

    Assets = storage.directories.get(
      CloudfilesConfig['containers']['assets']
    )
  end

  desc "Prepare production branch with latest changes in master."
  task :update_production_branch => :environment do
    master = Repo.commits("master").first
    production = Repo.commits("production").first

    if production
      last_commit = (production.tree / "COMMIT").data
    else
      last_commit = nil
      production = master
    end

    if last_commit == master.id
      puts "Warning: deploying commit #{last_commit} again!"
    end

    idx = Grit::Index.new(Repo)
    idx.current_tree = master.tree

    # Check whether asset bundles have changed
    if last_commit.nil? ||
        Repo.diff(last_commit,
                  master,
                  "config/assets.yml",
                  "app/stylesheets",
                  "public/javascripts",
                  "public/stylesheets").size > 0
      puts "Compressed assets changed, update required."
      `compass compile`
      Rake::Task["generate_assets"].invoke
      Dir["public/assets/**"].each do |file|
        idx.add(file, File.read(file))
      end
    else
      puts "Skip asset update."
      path = "public/assets"
      (production.tree / path).contents.each do |blob|
        name = "#{path}/#{blob.name}"
        idx.add(name, blob.data)
      end
    end

    # Add config files to the repository.
    puts "Config files."
    idx.add("config/shapado.yml", File.read("config/shapado.yml"))
    idx.add("config/database.yml", File.read("config/database.yml"))

    # Fill base commit number
    idx.add("COMMIT", master.id)

    idx.commit("Based on #{master.id}.", :head => "production",
               :parents => [production])
  end

  desc "Send the production branch to heroku."
  task :push_production_branch do
    puts "Pushing production branch."
    `git push -f heroku production:master`
  end

  namespace :assets do

    task :mathjax => :environment do
      mathjax_dir = "public/javascripts/MathJax"

      Dir["#{mathjax_dir}/**/*"].each do |path|
        next if File.directory? path
        file = File.new path
        relative_path = file.path.match(Regexp.new("#{Regexp.escape mathjax_dir}\/?(.*)"))[1]
        puts relative_path
        Assets.files.create(
          :key => "MathJax/#{relative_path}",
          :body => file,
          :public => true
        )
      end
    end

    task :wmd => :environment do
      wmd_dir = 'public/javascripts/wmd'

      wmd_files =
        %w(showdown.js
           jquery.wmd.min.js
           wmd.css
           jquery.wmd.mathjax.js
           jquery.wmd.js
           images/wmd-buttons.png)

      wmd_files.each do |path|
        Assets.files.create(
          :key => "wmd/#{path}",
          :body => File.new("#{wmd_dir}/#{path}"),
          :public => true
        )
      end

    end
  end
end

