# frozen_string_literal: true

module TgErrorNotifier
  class Configuration
    attr_accessor :enabled,
      :bot_token,
      :chat_id,
      :api_base,
      :environment,
      :app_name,
      :max_backtrace_lines,
      :ignored_exceptions,
      :ignored_environments,
      :open_timeout,
      :read_timeout,
      :logger,
      :include_backtrace,
      :active_job_enabled

    def initialize
      @enabled = true
      @bot_token = ENV["TELEGRAM_BOT_TOKEN"]
      @chat_id = ENV["TELEGRAM_ERRORS_CHAT_ID"]
      @api_base = "https://api.telegram.org"
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @app_name = ENV["TELEGRAM_ERRORS_APP_NAME"] || "Rails App"
      @max_backtrace_lines = 20
      @ignored_exceptions = [
        "ActionController::RoutingError",
        "ActiveRecord::RecordNotFound",
        "ActionController::UnknownFormat"
      ]
      @ignored_environments = ["test"]
      @open_timeout = 2
      @read_timeout = 5
      @logger = nil
      @include_backtrace = true
      @active_job_enabled = true
    end
  end
end
