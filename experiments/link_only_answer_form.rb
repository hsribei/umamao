ab_test 'Link only answer form' do
  alternatives :full_answer_form, :link_only_answer_form
  metrics :new_search_result
  identify { |c| c.identify_vanity(:exclude_guests => true) }
end
