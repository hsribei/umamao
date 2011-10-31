require 'singleton'

# Vanity expects an object that responds to #id.
class Umamao::UntrackedUser
  include Singleton

  def id
    '03571a60f217cf68f795875d108a73fa21e0c2bcce7f'
  end
end
