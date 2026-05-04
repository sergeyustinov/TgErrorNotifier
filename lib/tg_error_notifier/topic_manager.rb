# frozen_string_literal: true

require "net/http"
require "json"
require "set"

module TgErrorNotifier
  class TopicManager
    ICON_COLOR_RED = 0xFB6F5F
    MAX_TOPIC_NAME = 128

    def initialize(config)
      @config = config
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @topics = {} # grouping_key => message_thread_id
      @creating = Set.new
    end

    def thread_id_for(key, exception)
      name = nil

      @mutex.synchronize do
        # Wait if another thread is already creating this topic
        while @creating.include?(key)
          @condition.wait(@mutex, 10)
        end

        return @topics[key] if @topics.key?(key)

        @creating.add(key)
        name = topic_name(exception)
      end

      thread_id = create_topic(name)

      @mutex.synchronize do
        @topics[key] = thread_id if thread_id
        @creating.delete(key)
        @condition.broadcast
      end

      thread_id
    end

    private

    def topic_name(exception)
      name = "#{exception.class.name}: #{exception.message}"
      name = name.gsub(/\s+/, " ").strip
      name.length > MAX_TOPIC_NAME ? "#{name[0...MAX_TOPIC_NAME - 1]}…" : name
    end

    def create_topic(name)
      token = resolve(@config.bot_token)
      chat_id = resolve(@config.chat_id)
      uri = URI("#{resolve(@config.api_base)}/bot#{token}/createForumTopic")

      payload = {
        chat_id: chat_id,
        name: name,
        icon_color: @config.topic_icon_color || ICON_COLOR_RED
      }

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      http = build_http(uri)
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        data.dig("result", "message_thread_id")
      else
        log("createForumTopic failed: HTTP #{response.code} #{response.body}")
        nil
      end
    rescue StandardError => e
      log("createForumTopic error: #{e.class}: #{e.message}")
      nil
    end

    def build_http(uri)
      http = if @config.proxy?
        Net::HTTP.new(uri.host, uri.port, resolve(@config.proxy_addr), resolve(@config.proxy_port).to_i, resolve(@config.proxy_user), resolve(@config.proxy_pass))
      else
        Net::HTTP.new(uri.host, uri.port)
      end
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http
    end

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end

    def log(message)
      return unless @config.logger
      @config.logger.error("[TgErrorNotifier::TopicManager] #{message}")
    end
  end
end
