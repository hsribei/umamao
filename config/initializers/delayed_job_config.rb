Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_run_time = 10.minutes

# Run each DJ only once. If it failed, keep it's data
# so that we can investigate later
Delayed::Worker.max_attempts = 1
Delayed::Worker.destroy_failed_jobs = false

# HACK: Monkey-patch the MongoMapper::Document,
# so that we can receive e-mails when some task raises an error or fail
module MongoMapper::Document
  def error(job, exception)
    Airbrake.notify(exception)
  end

  def failure
    Airbrake.notify(:error_class => 'Delayed::Job failed')
  end
end
