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
      :active_job_enabled,
      :proxy_addr,
      :proxy_port,
      :proxy_user,
      :proxy_pass,
      :grouping_enabled,
      :grouping_window,
      :topics_enabled,
      :topic_icon_color,
      :topic_store_read,
      :topic_store_write,
      :buttons

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
      @proxy_addr = nil
      @proxy_port = nil
      @proxy_user = nil
      @proxy_pass = nil
      @grouping_enabled = false
      @grouping_window = 60
      @topics_enabled = false
      @topic_icon_color = nil
      # Persistent storage for named topics (created via capture_message topic:).
      # Without a store each process/restart would create a duplicate forum topic.
      #   topic_store_read  = ->(name) { ... }        # returns thread_id or nil
      #   topic_store_write = ->(name, thread_id) { ... }
      @topic_store_read = nil
      @topic_store_write = nil
      # Inline keyboard attached under the message. The gem does not interpret
      # the buttons: whatever the host returns goes to Telegram as is, so the
      # host is free to use url buttons, callback_data or web_app.
      #
      #   config.buttons = lambda do |kind:, source:, context:, fingerprint:, exception: nil, message: nil|
      #     [[{ text: "To the board", url: "https://example.com/e/#{token}" }]]
      #   end
      #
      # Return value: array of rows, each row an array of button hashes.
      # A flat array of buttons is accepted too and becomes a single row.
      # Return nil or [] for no keyboard. Errors raised inside are logged and
      # the message is still delivered, without the keyboard.
      @buttons = nil
    end

    def proxy?
      proxy_addr.present? && proxy_port.present?
    end
  end
end
