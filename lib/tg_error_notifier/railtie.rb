# frozen_string_literal: true

module TgErrorNotifier
  class Railtie < Rails::Railtie
    config.telegram_error_notifier = ActiveSupport::OrderedOptions.new

    initializer "tg_error_notifier.configure", after: :load_config_initializers do |app|
      options = app.config.telegram_error_notifier

      TgErrorNotifier.configure do |config|
        config.enabled = options.enabled unless options.enabled.nil?
        config.bot_token = options.bot_token unless options.bot_token.nil?
        config.chat_id = options.chat_id unless options.chat_id.nil?
        config.api_base = options.api_base unless options.api_base.nil?
        config.environment = options.environment unless options.environment.nil?
        config.app_name = options.app_name unless options.app_name.nil?
        config.max_backtrace_lines = options.max_backtrace_lines unless options.max_backtrace_lines.nil?
        config.ignored_exceptions = options.ignored_exceptions unless options.ignored_exceptions.nil?
        config.ignored_environments = options.ignored_environments unless options.ignored_environments.nil?
        config.open_timeout = options.open_timeout unless options.open_timeout.nil?
        config.read_timeout = options.read_timeout unless options.read_timeout.nil?
        config.logger = options.logger unless options.logger.nil?
        config.include_backtrace = options.include_backtrace unless options.include_backtrace.nil?
        config.active_job_enabled = options.active_job_enabled unless options.active_job_enabled.nil?
      end
    end

    initializer "tg_error_notifier.middleware" do |app|
      app.middleware.use TgErrorNotifier::Middleware
    end

    initializer "tg_error_notifier.subscriber", after: :load_config_initializers do
      TgErrorNotifier::Subscriber.attach! if TgErrorNotifier.configuration.active_job_enabled
    end
  end
end
