class Notifier < ActionMailer::Base
  layout 'notification'
  default :from => AppConfig.notification_email

  helper :application

  def give_advice(user, group, question, following = false)
    @user = user
    @group = group
    @question = question
    @following = following

    @domain = group.domain

    scope = "mailers.notifications.give_advice"

    if following
      subject = I18n.t("friend_subject", :scope => scope,
                     :question_title => question.title)
    else
      subject = I18n.t("subject", :scope => scope,
                     :question_title => question.title)
    end

    mail(:to => user.email, :subject => subject)
  end

  def new_question(user, group, question, topic)
    @user = user
    @group = group
    @question = question
    @domain = group.domain
    @topic = topic
    @disable_link = topic_url(@topic)

    scope = "mailers.notifications.new_question"

    subject = I18n.t("subject",
                     :scope => scope,
                     :topic => @topic.title)

    mail(:to => user.email, :subject => subject)
  end

  def new_answer(user, group, answer, following = false)
    @user = user     #question creator
    @group = group
    @answer = answer #answer.user
    @following = following

    @domain = group.domain
    @question = @answer.question

    scope = "mailers.notifications.new_answer"

    if user == answer.question.user
      subject = I18n.t("subject_owner",
                       :scope => scope,
                       :title => answer.question.title,
                       :name => answer.user.name)
    elsif following
      subject = I18n.t("subject_friend",
                       :scope => scope,
                       :title => answer.question.title,
                       :name => answer.user.name)
    else
      subject = I18n.t("subject_other",
                       :scope => scope,
                       :title => answer.question.title,
                       :name => answer.user.name)
    end

    mail(:to => user.email, :subject => subject)
  end

  def new_comment(user, group, comment, question)
    @user = user
    @group = group
    @comment = comment
    @question = question

    @domain = group.domain

    subject = I18n.t("mailers.notifications.new_comment.subject",
                     :name => comment.user.name, :group => group.name)

    mail(:to => user.email, :subject => subject)
  end

  def new_feedback(user, title, content, email, ip)
    @user = user
    @title = title
    @content = content
    @email = email
    @ip = ip

    recipients = AppConfig.exception_notification["exception_recipients"]
    subject = "feedback: #{title}"

    mail(:to => recipients, :subject => subject)
  end

  def user_accepted_suggestion(origin, user, entry)
    @user, @origin, @entry, @domain = user, origin, entry, AppConfig.domain

    subject = I18n.t(
      'mailers.notifications.user_accepted_suggestion',
      :user => user.name, :entry => entry.title)

    mail(:to => origin.email, :subject => subject)
  end

  def new_user_suggestion(user, origin, entry)
    @user, @origin, @entry, @domain = user, origin, entry, AppConfig.domain

    subject = I18n.t(
      'mailers.notifications.new_user_suggestion',
      :origin => origin.name, :entry => entry.title)

    mail(:to => user.email, :subject => subject)
  end

  def follow(user, followed)
    @user = user
    @followed = followed

    subject = I18n.t("mailers.notifications.follow.subject",
                     :name => user.name, :app => AppConfig.application_name)

    mail(:to => followed.email, :subject => subject)
  end

  def favorited(user, group, question)
    @user = user
    @group = group
    @question = question

    subject = I18n.t("mailers.notifications.favorited.subject",
                     :name => user.name)

    mail(:to => question.user.email, :subject => subject)
  end

  def report(user, report)
    @user = user
    @report = report

    subject = I18n.t("mailers.notifications.report.subject",
                     :group => report.group.name,
                     :app => AppConfig.application_name)

    mail(:to => user.email, :subject => subject)
  end

  def signup(affiliation)
    @affiliation_token = affiliation.affiliation_token
    mail(:to => affiliation.email, :subject => t("mailers.notifications.signup.subject"))
  end

  def closed_for_signup(affiliation)
    @university = affiliation.university
    @email = affiliation.email
    mail(:to => affiliation.email, :subject => t("mailers.notifications.closed_for_signup.subject"))
  end

  def wait(waiting_user)
    @open_universities = University.open_for_signup
    @email = waiting_user.email
    mail(:to => waiting_user.email, :subject => t("mailers.notifications.closed_for_signup.subject"))
  end

  def non_academic(waiting_user)
    @open_universities = University.open_for_signup
    @email = waiting_user.email
    mail(:to => waiting_user.email, :subject => t("mailers.notifications.closed_for_signup.subject"))
  end
end
