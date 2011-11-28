# -*- coding: utf-8 -*-

namespace :users do
  desc "Make all users active"
  task :make_users_active => :environment do
    User.set({}, :active => true)
  end
end
