require 'digest/sha1'

class University < Topic
  include MongoMapper::Document
  include Scopes
  include MongoMapperExt::Filter

  key :name, String, :length => 500, :index => true, :required => true,
    :unique => true
  key :short_name, String, :length => 500, :index => true, :required => true
  key :state, String, :length => 20
  key :open_for_signup, Boolean, :default => true
  key :validation_type, String, :default => 'email'
  key :domains, Array
  key :email_code_regexp, String

  has_many :affiliations, :dependent => :destroy

  timestamps!

  filterable_keys           :name, :short_name

  # Topics we want to suggest to affiliated users initially. We do not
  # include here subject topics, only topics of general
  # interest.
  key :university_topic_ids, Array, :default => []
  has_many :university_topics, :class_name => "Topic",
    :in => :university_topic_ids

  slug_key :title, :unique => true, :min_length => 3

  # It's short_name.desc, not .asc, because it's a quick heuristic for
  # now to show good Brazilian universities (Unicamp, Usp) first and
  # Harvard last (it would be weird if Harvard came first)
  scope :open_for_signup, where(:open_for_signup => true).sort(:short_name.desc)

  def email_regexp
    if self.domains.present?
      Regexp.new "([.@]" + self.domains.join("$)|([.@]") + "$)"
    end
  end

  def self.find_id_by_email_domain(email)
    University.all.each { |u|
      return u.id if email.strip =~ u.email_regexp
    }
    return nil
  end

  def self.find_by_email_domain(email)
    University.all.each { |u|
      return u if email.strip =~ u.email_regexp
    }
    return nil
  end

  # Return a student code based on his academic email, if possible
  def student_code_from_email(email)
    if self.email_code_regexp.present?
      email.match(Regexp.new self.email_code_regexp)[1]
    end
  end

  # Find a student of this university based on the email address.
  def find_student_by_email(email)
    Student.first(:code => self.student_code_from_email(email),
                  :university_id => self.id)
  end

end
