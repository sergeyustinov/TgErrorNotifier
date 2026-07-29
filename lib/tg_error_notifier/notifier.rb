# frozen_string_literal: true

require "net/http"
require "json"
require "cgi"

module TgErrorNotifier
  class Notifier
    MAX_MESSAGE_LENGTH = 3800
    # Отдельные поля (сообщение исключения, значения контекста) режем заранее,
    # чтобы гарантированно осталось место под бэктрейс и закрывающие теги
    MAX_FIELD_LENGTH = 900
    HTML_TAGS = %w[pre code b i u s].freeze

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

      key = nil
      thread_id = nil
      suppressed_count = 0

      if config.topics_enabled || config.grouping_enabled
        key = grouper.grouping_key(exception)
      end

      if config.topics_enabled
        thread_id = topic_manager.thread_id_for(key, exception)
      end

      if config.grouping_enabled
        result = grouper.process(key: key, thread_id: thread_id)
        if result[:action] == :suppress
          return { sent: false, status: :suppressed }
        end
        suppressed_count = result[:count]
        thread_id = result[:thread_id] || thread_id
      end

      payload = build_payload(
        exception: exception,
        source: source,
        context: context,
        thread_id: thread_id,
        suppressed_count: suppressed_count
      )
      response = send_payload(payload)

      if !response[:sent] && config.grouping_enabled && key
        grouper.rollback(key)
      end

      response
    rescue StandardError => e
      log("notify failed: #{e.class}: #{e.message}")
      { sent: false, status: :failed, reason: e.class.name, error: e.message }
    end

    def notify_message(message:, level:, source:, context: {}, topic: nil, thread_id: nil)
      enabled_check = enabled_status
      unless enabled_check[:enabled]
        log("skipped: #{enabled_check[:reason]}")
        return { sent: false, status: :skipped, reason: enabled_check[:reason] }
      end

      thread_id ||= topic_manager.thread_id_for_name(topic) if topic

      payload = build_message_payload(
        message: message,
        level: level,
        source: source,
        context: context,
        thread_id: thread_id
      )
      send_payload(payload)
    rescue StandardError => e
      log("notify_message failed: #{e.class}: #{e.message}")
      { sent: false, status: :failed, reason: e.class.name, error: e.message }
    end

    private

    attr_reader :config

    def grouper
      @grouper ||= Grouper.new(window: config.grouping_window)
    end

    def topic_manager
      @topic_manager ||= TopicManager.new(config)
    end

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

    def send_payload(payload, retry_plain: true)
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

      # Последний рубеж: разметка не распарсилась — шлём то же самое
      # обычным текстом, чтобы тело сообщения дошло в любом случае
      if retry_plain && parse_entities_error?(response)
        plain = payload.dup
        plain.delete(:parse_mode)
        plain[:text] = truncate(strip_html(payload[:text]))
        return send_payload(plain, retry_plain: false)
      end

      { sent: false, status: :failed, reason: "telegram_api_error", code: response.code.to_i, body: response.body.to_s }
    end

    def parse_entities_error?(response)
      response.code.to_i == 400 && response.body.to_s.include?("can't parse entities")
    end

    def build_payload(exception:, source:, context: {}, thread_id: nil, suppressed_count: 0)
      parts = [
        "<b>🚨 #{escape(resolve(config.app_name).to_s)}: #{escape(resolve(config.environment).to_s)}</b>",
        "<b>Source:</b> #{escape(clamp(source, MAX_FIELD_LENGTH))}",
        "<b>Exception:</b> <code>#{escape(exception.class.name)}</code>",
        "<b>Message:</b> #{escape(clamp(exception.message, MAX_FIELD_LENGTH))}"
      ]

      if suppressed_count > 0
        parts << "<b>🔁 +#{suppressed_count} more in last #{config.grouping_window}s</b>"
      end

      parts << context_block(context)

      text = truncate(parts.compact.join("\n"))

      if config.include_backtrace && exception.backtrace
        lines = exception.backtrace.first(config.max_backtrace_lines)
        header = "\n<b>Backtrace:</b>\n"
        # Бэктрейс режем по остатку бюджета ДО оборачивания в <pre>,
        # иначе финальный truncate обрезал бы текст внутри тега и Telegram
        # отвечал 400 "can't find end tag corresponding to start tag pre"
        budget = MAX_MESSAGE_LENGTH - text.length - header.length - "<pre></pre>".length
        if budget > 100
          bt = cut_escaped(escape(lines.join("\n")), budget)
          text = "#{text}#{header}<pre>#{bt}</pre>"
        end
      end

      payload = {
        chat_id: resolve(config.chat_id),
        text: truncate(text),
        parse_mode: "HTML",
        disable_web_page_preview: true
      }
      payload[:message_thread_id] = thread_id if thread_id
      payload
    end

    def context_block(context)
      return nil if context.nil? || context.empty?

      formatted = context.map { |k, v| "<b>#{escape(k.to_s)}:</b> #{escape(clamp(v, MAX_FIELD_LENGTH))}" }
      formatted.join("\n")
    end

    def build_message_payload(message:, level:, source:, context: {}, thread_id: nil)
      text = [
        "<b>ℹ️ #{escape(resolve(config.app_name).to_s)}: #{escape(resolve(config.environment).to_s)}</b>",
        "<b>Source:</b> #{escape(source.to_s)}",
        "<b>Level:</b> <code>#{escape(level.to_s)}</code>",
        "<b>Message:</b> #{escape(message.to_s)}",
        context_block(context)
      ].compact.join("\n")

      payload = {
        chat_id: resolve(config.chat_id),
        text: truncate(text),
        parse_mode: "HTML",
        disable_web_page_preview: true
      }
      payload[:message_thread_id] = thread_id if thread_id
      payload
    end

    def clamp(value, limit)
      text = value.to_s
      text.length > limit ? "#{text[0...limit]}…" : text
    end

    # Обрезка уже экранированного текста: не оставляем хвост от «&amp;»
    def cut_escaped(text, limit)
      return text if text.length <= limit

      text[0...limit].sub(/&[#a-zA-Z0-9]*\z/, "")
    end

    def truncate(text)
      return text if text.length <= MAX_MESSAGE_LENGTH

      close_tags(cut_escaped(text, MAX_MESSAGE_LENGTH - 20)) + "\n...truncated"
    end

    # Обрезка могла оставить незакрытый тег или его половину — Telegram
    # на таком отвечает 400 и сообщение не доходит вовсе
    def close_tags(text)
      text = text.sub(/<[^>]*\z/, "")

      HTML_TAGS.each do |tag|
        unclosed = text.scan("<#{tag}>").size - text.scan("</#{tag}>").size
        unclosed.times { text += "</#{tag}>" }
      end

      text
    end

    def strip_html(text)
      CGI.unescapeHTML(text.to_s.gsub(/<[^>]*>/, ""))
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
