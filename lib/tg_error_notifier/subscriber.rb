# frozen_string_literal: true

module TgErrorNotifier
  class Subscriber
    def self.attach!
      return if @attached

      ActiveSupport::Notifications.subscribe("perform.active_job") do |_name, _start, _finish, _id, payload|
        exception = payload[:exception_object]
        next unless exception

        job = payload[:job]
        TgErrorNotifier.notify(
          exception: exception,
          source: "active_job",
          context: {
            job_class: job&.class&.name,
            job_id: job&.job_id,
            queue: job&.queue_name,
            executions: job&.executions
          }
        )
      end

      @attached = true
    end
  end
end
