# frozen_string_literal: true

require "net/http"
require "json"
require "cgi"

module TgErrorNotifier
  class Notifier
    MAX_MESSAGE_LENGTH = 3800

    def initialize(config)
      @config = config
    end

    def notify(exception:, source:, context: {})
      enabled_check = enabled_status
      unless enabled_check[:enabled]
        log("skipped: #{enabled_check[:reason]}")
        return { sent: false, status: :skipped, reason: enabled_check[:reason] }
      end

      if ignored_exception?(exception)
        return { sent: false, status: :skipped, reason: "ignored_exception" }
      end

      payload = build_payload(exception: exception, source: source, context: context)
      send_payload(payload)
    rescue StandardError => e
      log("notify failed: #{e.class}: #{e.message}")
      { sent: false, status: :failed, reason: e.class.name, error: e.message }
    end

    def notify_message(message:, level:, source:, context: {})
      enabled_check = enabled_status
      unless enabled_check[:enabled]
        log("skipped: #{enabled_check[:reason]}")
        return { sent: false, status: :skipped, reason: enabled_check[:reason] }
      end

      payload = build_message_payload(message: message, level: level, source: source, context: context)
      send_payload(payload)
    rescue StandardError => e
      log("notify_message failed: #{e.class}: #{e.message}")
      { sent: false, status: :failed, reason: e.class.name, error: e.message }
    end

    private

    attr_reader :config

    def enabled_status
      return { enabled: false, reason: "disabled" } unless resolve(config.enabled)
      if config.ignored_environments.include?(resolve(config.environment).to_s)
        return { enabled: false, reason: "ignored_environment" }
      end

      token_present = resolve(config.bot_token).to_s != ""
      chat_present = resolve(config.chat_id).to_s != ""
      return { enabled: false, reason: "missing_bot_token" } unless token_present
      return { enabled: false, reason: "missing_chat_id" } unless chat_present

      { enabled: true }
    end

    def ignored_exception?(exception)
      ignored = config.ignored_exceptions.map(&:to_s)
      ignored.include?(exception.class.name)
    end

    def send_payload(payload)
      token = resolve(config.bot_token)
      uri = URI("#{resolve(config.api_base)}/bot#{token}/sendMessage")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      http = if config.proxy?
        Net::HTTP.new(uri.host, uri.port, resolve(config.proxy_addr), resolve(config.proxy_port).to_i, resolve(config.proxy_user), resolve(config.proxy_pass))
      else
        Net::HTTP.new(uri.host, uri.port)
      end
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = config.open_timeout
      http.read_timeout = config.read_timeout

      response = http.request(request)
      if response.is_a?(Net::HTTPSuccess)
        return { sent: true, status: :sent, code: response.code.to_i }
      end

      log("telegram api error: HTTP #{response.code} #{response.body}")
      { sent: false, status: :failed, reason: "telegram_api_error", code: response.code.to_i, body: response.body.to_s }
    end

    def build_payload(exception:, source:, context: {})
      text = [
        "<b>🚨 #{escape(resolve(config.app_name).to_s)}: #{escape(resolve(config.environment).to_s)}</b>",
        "<b>Source:</b> #{escape(source.to_s)}",
        "<b>Exception:</b> <code>#{escape(exception.class.name)}</code>",
        "<b>Message:</b> #{escape(exception.message.to_s)}",
        context_block(context)
      ].compact.join("\n")

      if config.include_backtrace && exception.backtrace
        lines = exception.backtrace.first(config.max_backtrace_lines)
        bt = escape(lines.join("\n"))
        text = "#{text}\n<b>Backtrace:</b>\n<pre>#{bt}</pre>"
      end

      {
        chat_id: resolve(config.chat_id),
        text: truncate(text),
        parse_mode: "HTML",
        disable_web_page_preview: true
      }
    end

    def context_block(context)
      return nil if context.nil? || context.empty?

      formatted = context.map { |k, v| "<b>#{escape(k.to_s)}:</b> #{escape(v.to_s)}" }
      formatted.join("\n")
    end

    def build_message_payload(message:, level:, source:, context: {})
      text = [
        "<b>ℹ️ #{escape(resolve(config.app_name).to_s)}: #{escape(resolve(config.environment).to_s)}</b>",
        "<b>Source:</b> #{escape(source.to_s)}",
        "<b>Level:</b> <code>#{escape(level.to_s)}</code>",
        "<b>Message:</b> #{escape(message.to_s)}",
        context_block(context)
      ].compact.join("\n")

      {
        chat_id: resolve(config.chat_id),
        text: truncate(text),
        parse_mode: "HTML",
        disable_web_page_preview: true
      }
    end

    def truncate(text)
      return text if text.length <= MAX_MESSAGE_LENGTH

      text[0...MAX_MESSAGE_LENGTH] + "\n...truncated"
    end

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end

    def escape(text)
      CGI.escapeHTML(text.to_s)
    end

    def log(message)
      return unless config.logger

      config.logger.error("[TgErrorNotifier] #{message}")
    end
  end
end
