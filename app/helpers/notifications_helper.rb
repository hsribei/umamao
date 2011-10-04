module NotificationsHelper

  def notification_message(notification)
    origin = notification.origin
    case notification.event_type
    when "new_answer", "new_comment", "new_search_result"
      question = notification.question
      I18n.t("notifications.#{notification.event_type}",
             :user => link_to(h(short_name(origin)), user_path(origin)),
             :question => link_to(h(question.title),
                                  question_path(question)))
    when "new_question"
      question = notification.question
      topic = notification.topic
      I18n.t("notifications.new_question",
             :user => link_to(h(short_name(origin)), user_path(origin)),
             :question => link_to(h(question.title),
                                  question_path(question)),
             :topic => link_to(h(topic.title), topic_path(topic)))
    when "follow"
      I18n.t("notifications.follow", :user => link_to(h(short_name(origin)),
                                                      user_path(origin)))
    when "new_answer_request"
      question = notification.question
      I18n.t("notifications.new_answer_request", 
             :user => link_to(h(short_name(origin)), user_path(origin)), 
             :question => link_to(h(question.title),
                                  question_path(question)))
    when 'new_user_suggestion', 'accepted_user_suggestion'
      topic = notification.topic
      I18n.t("user_suggestions.notifications.#{notification.event_type}",
             :user => link_to(h(short_name(origin)), user_path(origin)),
             :topic => link_to(h(topic.title), topic_path(topic)))
    end
  end
end

