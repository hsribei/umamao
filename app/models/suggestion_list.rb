class SuggestionList
  include MongoMapper::EmbeddedDocument

  belongs_to :user

  key :topic_suggestion_ids, Array, :default => []
  has_many :topic_suggestions, :class_name => "Suggestion",
    :in => :topic_suggestion_ids

  key :uninteresting_topic_ids, Array, :default => []
  has_many :uninteresting_topics, :class_name => "Topic",
    :in => :uninteresting_topic_ids

  key :user_suggestion_ids, Array, :default => []
  has_many :user_suggestions, :class_name => "Suggestion",
    :in => :user_suggestion_ids

  key :uninteresting_user_ids, Array, :default => []
  has_many :uninteresting_users, :class_name => "User",
    :in => :uninteresting_user_ids

  def has_been_suggested?(thing)
    if thing.is_a?(Topic)
      self.topic_suggestions.any?{|s| s.entry == thing}
    elsif thing.is_a?(User)
      self.user_suggestions.any?{|s| s.entry == thing}
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
  end

  # Add things to the user's suggestion lists, ignoring the ones that
  # were already suggested, followed, or marked as
  # uninteresting. Works on enumerables as well.
  #
  # options:
  # - limit: maximum number of things to suggest
  # - reason: the reason we are suggesting this thing to the user
  #
  def suggest(thing, options = {})
    limit = options[:limit]
    reason = options[:reason] || "calculated"

    # For some reason, the case statement wasn't working.
    if thing.is_a?(Topic)
      if !self.has_been_suggested?(thing) &&
          !self.user.following?(thing) &&
          !self.uninteresting_topic_ids.include?(thing.id)
        suggestion = Suggestion.new(:user => self.user,
                                    :entry_id => thing.id,
                                    :entry_type => thing.class.to_s,
                                    :reason => reason)
        self.topic_suggestions << suggestion
        return 1
      end
    elsif thing.is_a?(User)
      if !self.has_been_suggested?(thing) &&
          self.user.id != thing.id &&
          !self.user.following?(thing) &&
          !self.uninteresting_user_ids.include?(thing.id)
        suggestion = Suggestion.new(:user => self.user,
                                    :entry_id => thing.id,
                                    :entry_type => "User",
                                    :reason => reason)
        self.user_suggestions << suggestion
        return 1
      end
    elsif thing.respond_to?(:each)
      total = 0
      thing.each do |t|
        break if limit.present? && total >= limit
        total += self.suggest(t, :reason => reason)
      end
      return total
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
    return 0
  end

  # Remove a suggestion from the list of suggestions. Destroy the
  # suggestion.
  def remove_suggestion(suggestion_or_entry)
    return if suggestion_or_entry.blank?

    suggestion =
      if suggestion_or_entry.is_a?(Suggestion)
        suggestion_or_entry
      else
        Suggestion.first({ :entry_id => suggestion_or_entry.id,
                           :rejected_at => nil, :accepted_at => nil,
                           :origin_id => nil, :user_id => self.user.id })
      end

    if suggestion
      self.remove_from_suggestions!(suggestion.id, suggestion.entry_id)
    else
      self.remove_from_suggestions!(suggestion_or_entry.id)
    end
  end

  # Mark something as uninteresting. Uninteresting users and topics
  # will be ignored in future suggestions.
  def mark_as_uninteresting(thing)
    if thing.is_a?(Topic)
      if !self.uninteresting_topic_ids.include?(thing.id)
        self.uninteresting_topic_ids << thing.id
      end
    elsif thing.is_a?(User)
      if !self.uninteresting_user_ids.include?(thing.id)
        self.uninteresting_user_ids << thing.id
      end
    else
      raise "Entity can't be suggested to a user: #{thing.class}"
    end
  end

  # Refuse and destroy a suggestion. Refused suggestions cannot be
  # re-suggested.
  def refuse_suggestion(suggestion)
    entry = suggestion.entry
    self.mark_as_uninteresting(entry)
    suggestion.reject!
  end

  # Find suggestions from the user's external accounts.
  def suggest_from_outside(from = {})
    self.suggest_users_from_outside(from)
    self.suggest_topics_from_outside(from)
  end

  def suggest_users_from_outside(from = {})
    self.suggest(self.user.find_external_contacts(from), :reason => "external")
  end

  def suggest_topics_from_outside(from = {})
    self.suggest(self.user.find_external_topics(from), :reason => "external")
  end

  # Suggest the 20 most followed topics.
  def suggest_popular_topics(limit)
    self.suggest(Topic.query(:order => :followers_count.desc,
                             :limit => limit),
                 :reason => "popular")
  end


  # Suggest topics related to the user's group invitation.
  def suggest_from_group_invitation
    if group_invitation = GroupInvitation.all(:user_ids => self.user.id).first
      self.suggest(group_invitation.topics, "group_invitation")
    end
  end
  
  # Suggest topics listed in shapado.yml
  def suggest_first_topics
    topics = configured_suggestions
    return if topics.blank?
    topics.each do |t|
      self.suggest(t, "popular") if t.present?
    end
  end

  # Populate the user's suggestion list for the signup wizard.
  def find_first_suggestions
    if self.topic_suggestions.blank? &&
        self.user_suggestions.blank?
      self.suggest_first_topics
      self.suggest_users_from_outside
    end
  end

  # Recalculate suggestions for the user.
  def refresh_suggestions(type = :all)
    if [:all, :topics].include?(type)
      self.refresh_topic_suggestions
    else
      raise "Don't know how to suggest #{type}"
    end
  end

  def refresh_topic_suggestions
    kept_suggestions = []

    self.topic_suggestions.each do |topic_suggestion|
      if ["external"].include?(topic_suggestion.reason) &&
          topic_suggestion.entry.present?
        kept_suggestions << topic_suggestion
      else
        topic_suggestion.reject!
      end
    end

    count = Hash.new(0) # Scores for suggestions
    topics = configured_suggestions
    topics.each do |topic|
      next if self.user.following?(topic) ||
        self.uninteresting_topic_ids.include?(topic.id) ||
        kept_suggestions.any?{|suggestion| suggestion.entry == topic}
      count[topic.id] += 1
    end

    self.topic_suggestions = kept_suggestions

    count.to_a.sort{|a, b| -(a[1] <=> b[1])}[0 .. 29].each do |topic_count|
      self.topic_suggestions << Suggestion.new(:user => self.user,
                                               :entry_id => topic_count.first,
                                               :entry_type => "Topic",
                                               :reason => "calculated")
    end
  end

  def remove_from_suggestions!(*ids)
    ids.each do |an_id|
      user.
        collection.
        update({ :_id =>  user.id },
               { :$pull =>
                   { 'suggestion_list.user_suggestion_ids' => an_id,
                     'suggestion_list.topic_suggestion_ids' => an_id,
                     'suggestion_list.uninteresting_user_ids' => an_id,
                     'suggestion_list.uninteresting_topic_ids' => an_id } })
    end
  end

protected
  def configured_suggestions
    ids = AppConfig.topic_suggestion
    if ids.blank?
      []
    else
      ids.map{ |id| Topic.find_by_slug_or_id(id) }.select{ |t| t.present?}
    end
  end
end
