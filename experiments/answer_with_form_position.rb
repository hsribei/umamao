ab_test 'Answer with form position' do
  alternatives :below, :above
  metrics :new_search_result
  identify { |c| c.current_user ? c.current_user.id :
                                  Umamao::UntrackedUser.instance.id }
end
