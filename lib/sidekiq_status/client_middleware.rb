# -*- encoding : utf-8 -*-

module SidekiqStatus
  class ClientMiddleware
    def call(worker, item, queue, redis_pool = nil)
      worker = worker.constantize if worker.is_a?(String)
      return yield unless worker < SidekiqStatus::Worker

      # Don't start reporting status if the job is scheduled for the future
      # When perform_at/perform_in is called this middleware is invoked within the client process
      # and job arguments have 'at' parameter. If all middlewares pass the job
      # Sidekiq::Client#raw_push puts the job into 'schedule' sorted set.
      #
      # Later, Sidekiq server ruby process periodically polls this sorted sets and repushes all
      # scheduled jobs which are due to run. This repush invokes all client middlewares, but within
      # sidekiq server ruby process.
      #
      # Luckily for us, when job is repushed, it doesn't have 'at' argument.
      # So we can distinguish the condition of the middleware invokation: we don't create SidekiqStatus::Container
      # when job is scheduled to run in the future, but we create status container when previously scheduled
      # job is due to run.
      return yield if item['at']

      jid  = item['jid']
      args = item['args']
      status_job_id = worker.respond_to?(:status_job_id) ? worker.status_job_id(jid, args) : jid

      result = yield

      if result
        SidekiqStatus::Container.create(
          'jid'    => status_job_id,
          'worker' => worker.name,
          'queue'  => queue,
          'args'   => args
        )
      end

      result
    rescue Exception => exc
      SidekiqStatus::Container.load(status_job_id).delete rescue nil
      raise exc
    end
  end
end
