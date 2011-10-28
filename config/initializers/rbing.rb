if (application_id = AppConfig.bing['application_id'])
  require 'rbing'
  Bing = RBing.new(application_id)
end
