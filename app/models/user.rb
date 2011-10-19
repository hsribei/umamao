require 'digest/sha1'
require 'timeout'

class User
  include MongoMapper::Document
  include Support::Search::Searchable
  include Scopes
  include MongoMapperExt::Filter
  devise :database_authenticatable, :recoverable, :registerable, :rememberable,
         :token_authenticatable, :validatable, :confirmable, :trackable

  ROLES = %w[user moderator admin]
  LANGUAGE_FILTERS = %w[any user] + AVAILABLE_LANGUAGES
  LOGGED_OUT_LANGUAGE_FILTERS = %w[any] + AVAILABLE_LANGUAGES

  class Helper
    include Singleton
    include GravatarHelper::PublicMethods
    include UsersHelper
  end

  key :_id,                       String
  key :login,                     String, :index => true
  key :name,                      String, :index => true

  key :bio,                       String
  key :website,                   String
  key :location,                  String
  key :birthday,                  Time
  key :gender,                    String, :length => 1, :in => ['m', 'f', nil]
  key :description,               String
  key :new_user,                  Boolean, :default => true

  key :identity_url,              String
  key :role,                      String, :default => "user"
  key :last_logged_at,            Time

  key :preferred_languages,       Array, :default => []

  key :notification_opts,         NotificationConfig

  key :language,                  String, :default => 'pt-BR'
  key :timezone,                  String, :default => "Brasilia"
  key :language_filter,           String, :default => "user", :in => LANGUAGE_FILTERS

  key :ip,                        String

  key :default_subtab,            Hash

  key :followers_count,           Integer, :default => 0
  key :following_count,           Integer, :default => 0

  key :membership_list,           MembershipList

  key :feed_token,                String
  key :can_invite_without_confirmation, Boolean, :default => true

  has_one :avatar, :dependent => :destroy

  key :ignored_topics_count, :default => 0

  has_many :affiliations, :dependent => :destroy
  has_many :questions, :dependent => :destroy
  has_many :answers, :dependent => :destroy
  has_many :search_results, :dependent => :destroy
  has_many :comments, :dependent => :destroy
  has_many :votes, :dependent => :destroy
  has_many :external_accounts, :class_name => "UserExternalAccount",
    :dependent => :destroy
  has_many :notifications, :dependent => :destroy
  has_many :sent_notifications, :foreign_key => "origin_id",
    :class_name => "Notification", :dependent => :destroy
  has_many :contacts, :dependent => :destroy

  # Number of invitations the user still has.
  key :invitations_left, :required => true, :default => 3
  has_many :invitations, :foreign_key => "sender_id", :dependent => :nullify

  has_one :suggestion_list, :dependent => :destroy
  delegate :topic_suggestions, :user_suggestions, :suggest,
    :remove_suggestion, :mark_as_uninteresting, :refuse_suggestion,
    :refresh_suggestions, :find_first_suggestions, :to => :suggestion_list

  has_many :favorites, :class_name => "Favorite", :foreign_key => "user_id"

  has_many :news_updates, :foreign_key => :author_id
  has_many :news_items, :as => "recipient", :dependent => :destroy

  key :friend_list_id, String
  belongs_to :friend_list, :dependent => :destroy

  key :invitation_token, String

  attr_accessor :affiliation_token

  # New users should go through our signup wizard to connect their
  # external accounts, receive suggestions, etc.
  key :has_been_through_wizard, Boolean, :default => false

  # Whether or not the user has agreed with our privacy policy and
  # terms of service during signup.
  key :agrees_with_terms_of_service, Boolean, :default => false

  key :last_read_notifications_at, Time

  has_one :url_invitation, :foreign_key => :inviter_id, :dependent => :destroy

  before_create :create_friend_list, :create_notification_opts
  before_create :generate_uuid
  after_create Proc.new { |user| UrlInvitation.generate(user) }

  timestamps!

  before_validation :confirm_from_invitation, :strip_email

  validates_inclusion_of :language, :within => AVAILABLE_LANGUAGES
  validates_inclusion_of :role,  :within => ROLES

  validates_presence_of :name,
    :message => lambda { I18n.t("users.validation.errors.empty_name") }
  validates_length_of :name, :maximum => 100,
    :message => lambda { I18n.t("users.validation.errors.long_name") }
  filterable_keys :name

  validates_length_of       :bio, :maximum => 140,
    :message => lambda { I18n.t("users.validation.errors.long_bio") }
  validates_length_of       :description, :maximum => 500,
    :message => lambda { I18n.t("users.validation.errors.long_description") }

  validates_true_for :agrees_with_terms_of_service,
    :logic => lambda {
       self.agrees_with_terms_of_service?
    },
    :if => lambda { |u| u.new? },
    :message => lambda { I18n.t("users.validation.errors.did_not_agree") }

  validates_true_for :invitations_left,
    :logic => lambda {
      self.invitations_left.is_a?(Integer) &&
      self.invitations_left >= 0 ||
      self.invitations_left == "unlimited"
    }

  before_create :logged!
  after_create :accept_invitation
  after_create :create_suggestion_list
  after_create :create_contact_references
  after_create :associate_with_waiting_users

  scope :confirmed, where(:confirmed_at.ne => nil)
  scope :unconfirmed, where(:confirmed_at => nil)

  def upvotes_count
    # FIXME: this can be way better, if upvotes are kept on its on counter
    #        or maybe if upvotes_count is denormalized
    self.search_results.map{ |sr| sr.votes.count(:value => 1) }.reduce(0, &:+)
  end

  def description=(description)
    super(description.try(:strip))
  end

  def self.find_for_authentication(conditions={})
    first(conditions) || first(:login => conditions["email"])
  end

  def self.find_by_login_or_id(login)
    find_by_login(login) || find_by_id(login)
  end

  def self.find_experts(tags, langs = AVAILABLE_LANGUAGES, options = {})
    opts = {}
    opts[:limit] = 15
    opts[:select] = [:user_id]
    if except = options[:except]
      except = [except] unless except.is_a? Array
      opts[:user_id] = {:$nin => except}
    end

    user_ids = UserStat.all(opts.merge({:answer_tags => {:$in => tags}})).map(&:user_id)

    conditions = {"notification_opts.give_advice" => {:$in => ["1", true]},
                  :preferred_languages => langs}

    if group_id = options[:group_id]
      conditions["membership_list.#{group_id}"] = {:$exists => true}
    end

    u = User.find(user_ids, conditions.merge(:select => [:email, :login, :name, :language]))
    u ? u : []
  end

  def self.ignorers(topics)
    igs = Set.new

    topics.each do |topic|
      igs += UserTopicInfo.fields([:user_id]).query(:topic_id => topic.id,
                                                   :ignored_at.ne => nil).
                                                   map(&:user)
    end

    igs
  end

  def external_search_results
    self.search_results.where(:id.nin => self.answers.fields(:search_result_id).map(&:search_result_id))
  end

  def confirm_from_invitation
    return if !self.new?
    invitation = Invitation.find_by_invitation_token(self.invitation_token)
    if invitation && invitation.sender.can_invite_without_confirmation?
      self.confirmed_at = Time.now
    end
  end

  # This is used to let people in on sign up. If they're active, they
  # are allowed in, if not, they have to do something (like confirm
  # email) before being allowed to log in.
  def active?
    true
  end

  def confirmed_affiliation?
    self.affiliations.any?(&:confirmed?)
  end

  # Return true iff the user is affiliated with the university through
  # an affiliation object.
  def affiliated_with?(university)
    self.affiliations.first(:university_id => university.id).present?
  end

  def first_name
    return nil unless self.name
    self.name.split(/\s+/).first
  end

  # Return the avatar url based on the user's avatar configurations.
  #   parameters:
  #   - from: which avatar to try (uploaded, facebook, twitter, gravatar)
  #   - size: the size of the avatar in pixels
  #   - force: if set to true will force to use the found avatar even if it
  #     is the default one.
  #
  def avatar_url(from = nil, size = nil, force = true)
    case from
    when nil
      ["uploaded", "facebook", "twitter", "gravatar"].each do |location|
        url = avatar_url location, size, false
        return url if url
      end
      nil
    when "gravatar"
      Helper.instance.gravatar_url self.email, :size => size
    when "twitter"
      if account = self.twitter_account
        url = account.user_info['image']
        if url =~ /default_profile_images/
          if force
            size && size > 50 ? url.gsub("_normal.", "_bigger.") : url
          end
        elsif size && size > 50
          url.gsub("_normal.", ".")
        else
          url
        end
      end
    when "facebook"
      if account = self.facebook_account
        url = account.user_info['image']
        if size && size > 50
          url.gsub("type=square", "type=large")
        else
          url
        end
      end
    when "uploaded"
      if self.avatar
        size && size > 50 ? self.avatar.url : self.avatar.url(:thumb)
      end
    end
  end

  # Update the user's avatar. If given a file, create an Avatar model;
  # otherwise, simply update the avatar_config field.
  def update_avatar(file)
    old_avatar = self.avatar
    new_avatar = Avatar.new(:file => file, :user => self)
    if new_avatar.save
      self.avatar = new_avatar
      old_avatar.destroy if old_avatar.present?
      self.needs_to_update_search_index
      self.save!
      true
    else
      false
    end
  end

  # Remove the current uploaded avatar, if it exists. Return true if
  # the avatar was destroyed, false otherwise.
  def remove_avatar
    if self.avatar.present?
      self.avatar.destroy
      self.needs_to_update_search_index
      self.save!
      true
    else
      false
    end
  end

  def accept_invitation
    invitation = Invitation.find_by_invitation_token(self.invitation_token)
    if invitation
      invitation.accepted_at = Time.now
      invitation.recipient_id = self.id
      invitation.save
    end
  end

  def add_preferred_tags(t, group)
    if t.kind_of?(String)
      t = t.split(",").join(" ").split(" ")
    end
    self.collection.update({:_id => self._id, "membership_list.#{group.id}.preferred_tags" =>  {:$nin => t}},
                    {:$pushAll => {"membership_list.#{group.id}.preferred_tags" => t}},
                    {:upsert => true})
  end

  def remove_preferred_tags(t, group)
    if t.kind_of?(String)
      t = t.split(",").join(" ").split(" ")
    end
    self.class.pull_all({:_id => self._id}, {"membership_list.#{group.id}.preferred_tags" => t})
  end

  def preferred_tags_on(group)
    @group_preferred_tags ||= (config_for(group).preferred_tags || []).to_a
  end

  def update_language_filter(filter)
    if LANGUAGE_FILTERS.include? filter
      User.set({:_id => self.id}, {:language_filter => filter})
      true
    else
      false
    end
  end

  def languages_to_filter
    @languages_to_filter ||= begin
      languages = nil
      case self.language_filter
      when "any"
        languages = AVAILABLE_LANGUAGES
      when "user"
        languages = (self.preferred_languages.empty?) ? AVAILABLE_LANGUAGES : self.preferred_languages
      else
        languages = [self.language_filter]
      end
      languages
    end
  end

  def is_preferred_tag?(group, *tags)
    ptags = config_for(group).preferred_tags
    tags.detect { |t| ptags.include?(t) }
  end

  def admin?
    self.role == "admin"
  end

  def age
    return if self.birthday.blank?

    Time.zone.now.year - self.birthday.year - (self.birthday.to_time.change(:year => Time.zone.now.year) >
Time.zone.now ? 1 : 0)
  end

  def can_modify?(model)
    return false unless model.respond_to?(:user)
    self.admin? || self == model.user
  end

  def groups(options = {})
    options[:order] ||= "activity_rate desc"
    self.membership_list.groups(options)
  end

  def member_of?(group)
    if group.kind_of?(Group)
      group = group.id
    end

    self.membership_list.has_key?(group)
  end

  def role_on(group)
    config_for(group, false).role
  end

  def owner_of?(group)
    admin? || group.owner_id == self.id || role_on(group) == "owner"
  end

  def mod_of?(group)
    owner_of?(group) || role_on(group) == "moderator" || self.reputation_on(group) >= group.reputation_constrains["moderate"].to_i
  end

  def editor_of?(group)
    if c = config_for(group, false)
      c.is_editor
    else
      false
    end
  end

  def user_of?(group)
    mod_of?(group) || self.membership_list.has_key?(group.id)
  end

  def main_language
    @main_language ||= self.language.split("-").first
  end

  def has_voted?(voteable)
    !vote_on(voteable).nil?
  end

  def vote_on(voteable)
    Vote.first(:voteable_type => voteable.class.to_s,
               :voteable_id => voteable.id,
               :user_id     => self.id )
  end

  def favorite?(question)
    !favorite(question).nil?
  end

  def favorite(question)
    self.favorites.first(:question_id => question._id, :user_id => self._id )
  end

  def logged!(group = nil)
    now = Time.zone.now

    if new?
      self.last_logged_at = now
    elsif group && (member_of?(group) || !group.private)
      on_activity(:login, group)
    end
  end

  def on_activity(activity, group)
    if activity == :login
      self.last_logged_at ||= Time.now
      if !self.last_logged_at.today?
        self.set( {:last_logged_at => Time.zone.now.utc} )
      end
    else
      self.update_reputation(activity, group) if activity != :login
    end
    activity_on(group, Time.zone.now)
  end

  def activity_on(group, date)
    day = date.utc.at_beginning_of_day
    last_day = config_for(group).last_activity_at

    if last_day != day
      self.set({"membership_list.#{group.id}.last_activity_at" => day})
      if last_day
        if last_day.utc.between?(day.yesterday - 12.hours, day.tomorrow)
          self.increment({"membership_list.#{group.id}.activity_days" => 1})
        elsif !last_day.utc.today? && (last_day.utc != Time.now.utc.yesterday)
          Rails.logger.info ">> Resetting act days!! last known day: #{last_day}"
          reset_activity_days!(group)
        end
      end
    end
  end

  def reset_activity_days!(group)
    self.set({"membership_list.#{group.id}.activity_days" => 0})
  end

  def upvote!(group, v = 1.0)
    self.increment({"membership_list.#{group.id}.votes_up" => v.to_f})
  end

  def downvote!(group, v = 1.0)
    self.increment({"membership_list.#{group.id}.votes_down" => v.to_f})
  end

  def update_reputation(key, group)
    value = group.reputation_rewards[key.to_s].to_i
    value = key if key.kind_of?(Integer)
    Rails.logger.info "#{self.login} received #{value} points of karma by #{key} on #{group.name}"
    current_reputation = config_for(group).reputation

    if value
      self.increment({"membership_list.#{group.id}.reputation" => value})
    end

    stats = self.reputation_stats(group, { :select => [:_id] })
    stats.save if stats.new?

    event = ReputationEvent.new(:time => Time.now, :event => key,
                                :reputation => current_reputation,
                                :delta => value )
    ReputationStat.collection.update({:_id => stats.id}, {:$addToSet => {:events => event.attributes}})
  end

  def reputation_on(group)
    config_for(group, false).reputation.to_i
  end

  def stats(*extra_fields)
    fields = [:_id]
    UserStat.find_or_create_by_user_id(self._id, :select => fields+extra_fields)
  end

  def follow(user)
    return false if user == self
    FriendList.push_uniq(self.friend_list_id, :following_ids => user.id)
    FriendList.push_uniq(user.friend_list_id, :follower_ids => self.id)

    User.increment(self.id, :following_count => 1)
    User.increment(user.id, :followers_count => 1)

    if user.notification_opts.activities
      old_notification =
        user.notifications.all(:event_type => "follow",
                               :origin_id => self.id,
                               :created_at.gte => Time.now - 1.week)
      if old_notification.blank?
        Notifier.delay.follow(self, user)
        Notification.create!(:user => user,
                             :event_type => "follow",
                             :origin => self)
      end
    end

    self.remove_suggestion(user)
    true
  end

  def unfollow(user)
    return false if user == self
    FriendList.pull(self.friend_list_id, :following_ids => user.id)
    FriendList.pull(user.friend_list_id, :follower_ids => self.id)

    User.decrement(self.id, :following_count => 1)
    User.decrement(user.id, :followers_count => 1)

    self.mark_as_uninteresting(user)
    true
  end

  def add_user_suggestion(origin, thing)
    us = UserSuggestion.new(
      :origin_id => origin.id,
      :user_id => self.id,
      :entry_id => thing.id,
      :entry_type => thing.collection.name.singularize.camelize,
      :reason => 'UserSuggested'
    )
    us.save!
  end

  def ignore_topic!(topic)
    user_topic = UserTopicInfo.first(:user_id => self.id, :topic_id => topic.id)
    if user_topic && user_topic.ignored?
      return
    end

    if user_topic
      user_topic.ignore!
      topic.remove_follower!(self)
    else
      UserTopicInfo.create(:user_id => self.id, :topic_id => topic.id,
                           :ignored_at => Time.now)
    end
    self.increment(:ignored_topics_count => 1)
    self.hide_ignored_news_items!
  end

  def unignore_topic!(topic)
    if user_topic = UserTopicInfo.first(:user_id => self.id,
                                         :topic_id => topic.id,
                                         :ignored_at.ne => nil)
      user_topic.unignore!
      self.increment(:ignored_topics_count => -1)
      self.show_unignored_news_items!
    end
  end

  def ignores?(topic)
    UserTopicInfo.first(:topic_id => topic.id, :user_id => self.id,
                        :ignored_at.ne  => nil).present?
  end

  def hide_ignored_news_items!(news_items = self.news_items)
    news_items.each do |ni|
      if ni.should_be_hidden?(self.ignored_topic_ids)
        ni.hide!
      end
    end
  end
  handle_asynchronously :hide_ignored_news_items!

  def show_unignored_news_items!(news_items = self.news_items)
    news_items.each do |ni|
      unless ni.should_be_hidden?(self.ignored_topic_ids)
        ni.show!
      end
    end
  end
  handle_asynchronously :show_unignored_news_items!

  def followers
    self.friend_list.followers
  end

  def following
    self.friend_list.following
  end

  def following?(followable)
    if followable.is_a? User
      friend_list(:select => [:following_ids]).following_ids.include?(followable.id)
    elsif followable.is_a? Topic
      UserTopicInfo.count(:user_id => self.id,
                                 :topic_id => followable.id,
                                 :followed_at.ne => nil) > 0
    else
      raise "User can't follow a #{followable.class}"
    end
  end

  def viewed_on!(group)
    self.collection.update({:_id => self._id},
                           {:$inc => {"membership_list.#{group.id}.views_count" => 1.0}},
                            :upsert => true)
  end

  def method_missing(method, *args, &block)
    if !args.empty? && method.to_s =~ /can_(\w*)\_on?/
      key = $1
      group = args.first
      if group.reputation_constrains.include?(key.to_s)
        if group.has_reputation_constrains
          return self.owner_of?(group) || self.mod_of?(group) || (self.reputation_on(group) >= group.reputation_constrains[key].to_i)
        else
          return true
        end
      end
    end
    super(method, *args, &block)
  end

  def config_for(group, init = true)
    if group.kind_of?(Group)
      group = group.id
    end

    config = self.membership_list[group]
    if config.nil?
      if init
        config = self.membership_list[group] = Membership.new(:group_id => group)
      else
        config = Membership.new(:group_id => group)
      end
    end
    config
  end

  def reputation_stats(group, options = {})
    if group.kind_of?(Group)
      group = group.id
    end
    default_options = { :user_id => self.id,
                        :group_id => group}
    stats = ReputationStat.first(default_options.merge(options)) ||
            ReputationStat.new(default_options)
  end

  def has_flagged?(flaggeable)
    flaggeable.flags.first(:user_id=>self.id)
  end

  def generate_uuid
    self.feed_token = UUIDTools::UUID.random_create.hexdigest
  end

  # Attempts to add more updates from origin to the user's feed when
  # it is too small
  def populate_news_feed!(origin)
    limit = self.news_items.count > 1000 ? 5 : 100
    total_feeded = 0
    case origin
    when User
      NewsUpdate.query(
        :author_id => origin.id,
        :order => :created_at.desc
      ).each do |update|
        return if total_feeded >= limit
        if NewsItem.query(:recipient_id => self.id,
                          :recipient_type => "User",
                          :news_update_id => update.id).count == 0
          NewsItem.notify!(update, self, origin, update.created_at)
          total_feeded += 1
        end
      end
    when Topic
      NewsItem.query(
        :recipient_id => origin.id,
        :recipient_type => "Topic",
        :order => :created_at.desc
      ).each do |item|
        return if total_feeded >= limit
        if NewsItem.query(:recipient_id => self.id,
                          :recipient_type => "User",
                          :news_update_id => item.news_update_id).count == 0
          NewsItem.notify!(item.news_update, self, origin, item.created_at)
          total_feeded += 1
        end
      end
    end
  end
  handle_asynchronously :populate_news_feed!

  # Return the user's associated Facebook account, if there is one,
  # and nil otherwise.
  def facebook_account
    self.external_accounts.first(:provider => "facebook")
  end

  # Return a Koala::Facebook::GraphAPI object to access the user's
  # Facebook account, or nil if the user doesn't have an associated
  # account.
  def facebook_connection
    if account = self.facebook_account
      return Koala::Facebook::GraphAPI.new(account.credentials["token"])
    end

    return nil
  end

  # Return the user's associated Twitter account, if there is one, and
  # nil otherwise.
  def twitter_account
    self.external_accounts.first(:provider => "twitter")
  end

  # Return a Twitter::Client object to access the user's Twitter
  # account, or nil if the user doesn't have an associated account.
  def twitter_client
    if account = self.twitter_account
      Twitter.configure do |config|
        config.consumer_key = AppConfig.twitter['key']
        config.consumer_secret = AppConfig.twitter['secret']
        config.oauth_token = account.credentials['token']
        config.oauth_token_secret = account.credentials['secret']
      end

      return Twitter::Client.new
    end

    return nil
  end

  # Return the user's associated DAC account, if there is one, and
  # nil otherwise.
  def dac_account
    self.external_accounts.first(:provider => "dac")
  end

  # Return a Student object to access the user's DAC account, or
  # nil if the user doesn't have an associated account.
  def dac_client
    if account = self.dac_account
      return Student.find_by_id(account.user_info['student'])
    end

    return nil
  end

  # Find users using self's external accounts. We simply ignore errors
  # when we stumble upon them.
  def find_external_contacts(from = {})
    from.reverse_merge!({'facebook' => true, 'twitter' => true})

    external_contacts = Set.new

    if from['facebook']
      # Look in Facebook
      begin
        if account = self.facebook_account
          graph = Koala::Facebook::GraphAPI.new(account.credentials["token"])
          ids = graph.get_connections("me", "friends").map {|friend| friend["id"]}
          external_contacts += ExternalAccount.query(:provider => "facebook",
                                                     :uid.in => ids).map(&:user)
        end
      rescue Koala::Facebook::APIError
        # Ignore
      end
    end

    if from['twitter']
      # Look in Twitter
      begin
        if client = self.twitter_client
          ids = client.friends.users.map {|friend| friend.id.to_s}
          external_contacts += ExternalAccount.query(:provider => "twitter",
                                                     :uid.in => ids).map(&:user)
        end
      rescue Twitter::Error
        # Ignore
      end
    end

    external_contacts.to_a
  end

  # Find interesting topics using self's external accounts.
  def find_external_topics(from = {})
    from.reverse_merge!({'facebook' => true})

    topics = Set.new

    if from['twitter']
      begin
        if account = self.facebook_account
          graph = Koala::Facebook::GraphAPI.new(account.credentials["token"])
          likes = graph.get_connections("me", "likes")
          likes.each do |like|
            topic = Topic.first(:title => [/^#{Regexp.escape like["name"]}/i])
            if topic
              topics << topic
            end
          end
        end
      rescue Koala::Facebook::APIError
        # Ignore
      end
    end

    topics
  end

  def can_post_more_answers_on?(question)
    return Answer.count(:question_id => question.id, :user_id => self.id) == 0
  end

  # HACK - As we cannot provide translations for validatable
  # validations set up by devise, we translate them by hand.
  def translate_errors
    if self.errors[:email].present?
      self.errors[:email].map! do |error|
        case error
        when "can't be empty"
          I18n.t("users.validation.errors.empty_email")
        when "has already been taken"
          I18n.t("users.validation.errors.dup_email")
        when "is invalid"
          I18n.t("users.validation.errors.invalid_email")
        else
          error
        end
      end
    end

    if self.errors[:password].present?
      self.errors[:password].map! do |error|
        case error
        when "doesn't match confirmation"
          I18n.t("users.validation.errors.password_match")
        when "is invalid"
          I18n.t("users.validation.errors.invalid_password")
        when "can't be empty"
          I18n.t("users.validation.errors.empty_password")
        else
          error
        end
      end
    end
  end

  def search_entry
    {
      :id => self.id,
      :title => self.name,
      :photo_url => Helper.instance.avatar_for(self, :size => 20),
      :entry_type => "User"
    }
  end

  # Updates caused by changes in external accounts are handled by the
  # external accounts class.
  def needs_to_update_search_index?
    self.name_changed? || super
  end

  # Return all unread notifications
  def unread_notifications
    if date = self.last_read_notifications_at
      self.notifications.query(:created_at.gt => date)
    else
      self.notifications
    end
  end

  # Start a contact import session with Cloudsponge.
  def begin_contact_import(provider)
    importer =
      Cloudsponge::ContactImporter.new(AppConfig.cloudsponge["key"],
                                       AppConfig.cloudsponge["password"])
    importer.begin_import(provider)
  end

  # Fetch contacts from Cloudsponge.
  def import_contacts!(import_id)
    importer =
      Cloudsponge::ContactImporter.new(AppConfig.cloudsponge["key"],
                                       AppConfig.cloudsponge["password"])

    fetched_contacts = nil

    begin
      Timeout.timeout(180) do # 3 minute timeout
        loop do
          events = importer.get_events import_id
          if events.any?(&:is_complete?)
            fetched_contacts, owner = importer.get_contacts(import_id)
            break
          elsif events.any?(&:is_error?)
            raise Shapado::ContactImportException.
              new("Cloudsponge returned error")
          end
        end
      end
    rescue Timeout::Error, Cloudsponge::CsException => e
      raise Shapado::ContactImportException.new(e.message)
    end

    [].tap{ |imported_contacts|
      fetched_contacts.each do |contact|
        if (c = self.contacts.first(:email => contact.email))
          imported_contacts << c
        else
          c = Contact.new(:user => self,
                          :name => contact.name,
                          :email => contact.email)

          # Check whether this contact exists already in the DB.
          c.corresponding_user = User.find_by_email(c.email)

          # Check whether this contact was already invited by the user.
          c.invitation = self.invitations.first(:recipient_email => c.email)

          imported_contacts << c if c.save
        end
      end
    }

    return true
  end

  # Invite emails for group sending message. Check whether there are
  # enough invitations left.
  def invite!(emails, group, message)
    if emails.present? && self.can_invite?(emails.size)
      count, faulty_emails =
        Invitation.invite_emails!(self, group, message, emails)

      if self.invitations_left.is_a? Numeric
        self.invitations_left -= count
        self.save!
      end

      [count, faulty_emails]
    else
      [nil, []]
    end
  end

  # Return true if user can invite n contacts, false otherwise.
  def can_invite?(n = 1)
    self.invitations_left == "unlimited" ||
      self.invitations_left >= n
  end

  def ignored_topic_ids
    UserTopicInfo.fields([:topic_id]).
      query(:user_id => self.id, :ignored_at.ne => nil).map(&:topic_id)
  end

  def associate_with_waiting_users
    emails = [self.email]
    if self.affiliations.present?
      emails += self.affiliations.map(&:email)
      emails = emails.uniq
    end

    WaitingUser.find_each(:email.in => emails) do |wu|
      wu.user = self
      wu.save!
    end
  end

  protected
  def password_required?
    (encrypted_password.blank? || !password.blank?)
  end

  def create_friend_list
    if !self.friend_list.present?
      self.friend_list = FriendList.new
    end
  end

  def create_notification_opts
    if !self.notification_opts
      self.notification_opts = NotificationConfig.new
    end
  end

  def strip_email
    self.email = self.email.strip
  end

  # Create a suggestion list for the user. Used with an after_create.
  def create_suggestion_list
    self.suggestion_list = SuggestionList.new(:user => self)
    self.save :validate => false
  end

  # Search for the user in every imported external contact and create
  # references to it.
  def create_contact_references
    Contact.query(:email => self.email).each do |contact|
      contact.corresponding_user = self
      contact.save!
    end
  end
end
