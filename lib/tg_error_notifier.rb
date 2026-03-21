# frozen_string_literal: true

require "rails"
require_relative "tg_error_notifier/version"
require_relative "tg_error_notifier/configuration"
require_relative "tg_error_notifier/notifier"
require_relative "tg_error_notifier/middleware"
require_relative "tg_error_notifier/subscriber"
require_relative "tg_error_notifier/railtie"

module TgErrorNotifier
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def notify(exception:, source:, context: {})
      notifier.notify(exception: exception, source: source, context: context)
    end

    # API similar to Sentry.capture_exception(error)
    def capture_exception(exception, source: "manual", context: {})
      notify(exception: exception, source: source, context: context)
    end

    # API similar to Sentry.capture_message("text")
    def capture_message(message, level: :info, source: "manual", context: {})
      notifier.notify_message(message: message, level: level, source: source, context: context)
    end

    private

    def notifier
      @notifier ||= Notifier.new(configuration)
    end
  end
end
