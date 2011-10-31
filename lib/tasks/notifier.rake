namespace :notifier do
  def check_notifier(method_name, *params)
    puts Notifier.send(method_name, *params)
  end

  desc 'Check emails'
  task :check_emails => :environment do
    user, another_user = User.all(:limit => 2, :order => 'created_at.desc')
    question = Question.first
    answer = Answer.first
    group = Group.first
    q_comment = Comment.where(:commentable_type => 'Question').first
    sr_comment = Comment.where(:commentable_type => 'SearchResult').first
    topic = Topic.first
    search_result = SearchResult.first
    waiting_user = WaitingUser.first
    user_suggestion = UserSuggestion.first
    affiliation = Affiliation.first

    notifier_data = {
      :favorited =>
        [:favorited, user, question.group, question],
      :follow =>
        [:follow, user, another_user],
      :new_answer =>
        [:new_answer, user, answer.group, answer],
      :new_answer_follow =>
        [:new_answer, user, answer.group, answer, true],
      :new_question_comment =>
        [:new_comment, q_comment, { :recipient => user }],
      :new_search_result_comment =>
        [:new_comment, sr_comment, { :recipient => user }],
      :new_feedback =>
        [:new_feedback, user, 'Feedback title', 'Feedback content',
         'feedbackemail.com', '127.0.0.0'],
      :new_question =>
        [:new_question, user, question.group, question, topic],
      :new_search_result =>
        [:new_search_result, user, group, search_result],
      :new_user_suggestion =>
        [:new_user_suggestion, user_suggestion.user, user_suggestion.origin,
         user_suggestion.entry],
      # TODO: create :report check; couldn't find any reference to it
      :signup =>
        [:signup, affiliation],
      :survey =>
        [:survey, user],
      :user_accepted_suggestion =>
        [:user_accepted_suggestion, user_suggestion.origin,
         user_suggestion.user, user_suggestion.entry],
      :wait =>
        [:wait, waiting_user]
    }

    notifier_data.each do |name, params|
      check_notifier(*params)
    end
  end
end
