Airbrake.configure do |config|
  config.api_key = AppConfig.airbrake['api_key']
  config.ignore << 'Goalie::NotFound'
end
