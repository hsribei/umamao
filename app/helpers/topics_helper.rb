# -*- coding: utf-8 -*-
module TopicsHelper

  # Small topic container used throughout the site.
  # options:
  #  - classifiable: the object that this topic classifies
  #  - ajax_add: whether this topic is being added on a form or not
  def topic_box(topic, options = {})
    classifiable = options[:classifiable]
    url = url_for(classifiable)
    class_name = classifiable.class.to_s.underscore
    "<li><div class='topic'><span class='topic-title'>#{link_to_topic(topic)}</span>
    #{
      if options[:logged_in] or (self.respond_to?(:logged_in?) and logged_in?)
        if classifiable && options[:ajax_add]
          "<a class='remove' href='#{url}/unclassify?topic=#{h(topic.title)}'>✕</a>"
        else
          "<input type='hidden' name='#{class_name}[topics][]' value='#{topic.title}'/><span class='remove'>✕</span>"
        end
      end
    }</div></li>"
  end

  # this should be defined as
  # link_to_topic(topic, text, options)
  # but as ruby1.8 doesn't support named parameters,
  # this workaround was done
  def link_to_topic(topic, *parameters)
    case parameters.size
    when 1:
      if parameters[0].is_a? String
        text = parameters[0]
      elsif parameters[0].is_a? Hash
        options = parameters[0]
      end
    when 2:
      text = parameters[0]
      options = parameters[1]
    end

    text ||= topic.title
    options ||= {}

    link_to h(text), topic_url(topic), :data => h(topic_tooltip(topic, options))
  end

  def topic_tooltip(topic, options = {})
    options.reverse_merge! :render_follow_button => true
    button_or_nothing =
      if logged_in? && options[:render_follow_button]
        "<div class=\"follow-info\">#{follow_button topic}</div>"
      else
        ""
      end

    desc = Rails.cache.fetch("topic_tt_desc.#{topic.id}.#{topic.updated_at}") do
      #FIXME: hide topic's description while there is no i18n for it

      #if topic.description.present?
      #  text = strip_tags(markdown(topic.description, :render_links => false))
      #  link_to truncate_words(text), topic_path(topic)
      #else
        link_to t('topics.tooltip.describe', :title => topic.title),
            edit_topic_path(topic)
      #end
    end

    "<div class='tooltip topic-tooltip'><span class='followers-count'>#{
        t('followable.followers', :count => topic.followers_count)
    }</span>#{button_or_nothing}
    "
    #FIXME: hide topic's description while there is no i18n for it
    # <hr/><div class='description'>#{desc}</div></div>"

  end

  def topic_help_text(topic)
    #FIXME: hide topic's description while there is no i18n for it

    #if topic.description.present?
    #  truncate_words(remove_links(topic.description), 100)
    #else
      topic.title
    #end
  end

  def embed_topic_tag(topic, method)
    case method
    when :js
      "<script src=\"#{embedded_topic_url(topic)}\"></script>"
    when :iframe
      "<iframe src=\"#{embedded_topic_url(topic)}\" frameborder=\"0\"" +
        "style=\"width: 500px; height: 210px;\"></iframe>"
    else
      raise "Invalid embedding method"
    end
  end
  private

  def remove_links(description)
    description.gsub(/\[([^\]]*)\]\[\d*\]/, '\1').gsub(/\[\d*\]: [^ ]*/, '').gsub(/ +/, " ").gsub(/[\r\n]/, '')
  end

end
