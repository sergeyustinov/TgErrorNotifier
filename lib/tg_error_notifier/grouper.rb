# frozen_string_literal: true

module TgErrorNotifier
  class Grouper
    Entry = Struct.new(:count, :first_at, :last_sent_at, :thread_id, keyword_init: true)

    CLEANUP_INTERVAL = 100

    def initialize(window:)
      @window = window
      @mutex = Mutex.new
      @entries = {}
      @call_count = 0
    end

    # Returns:
    #   { action: :send, count: N, thread_id: id_or_nil }
    #   { action: :suppress }
    def process(key:, thread_id: nil)
      now = Time.now

      @mutex.synchronize do
        @call_count += 1
        lazy_cleanup!(now) if (@call_count % CLEANUP_INTERVAL).zero?

        entry = @entries[key]

        if entry.nil?
          @entries[key] = Entry.new(count: 0, first_at: now, last_sent_at: now, thread_id: thread_id)
          return { action: :send, count: 0, thread_id: thread_id }
        end

        entry.thread_id = thread_id if entry.thread_id.nil? && thread_id

        elapsed = now - entry.last_sent_at

        if elapsed >= @window
          accumulated = entry.count
          entry.count = 0
          entry.last_sent_at = now
          { action: :send, count: accumulated, thread_id: entry.thread_id }
        else
          entry.count += 1
          { action: :suppress }
        end
      end
    end

    def rollback(key)
      @mutex.synchronize do
        @entries.delete(key)
      end
    end

    def grouping_key(exception)
      "#{exception.class.name}:#{normalize_message(exception.message)}"
    end

    private

    def normalize_message(message)
      msg = message.to_s
      msg = msg.gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "<UUID>")
      msg = msg.gsub(/\b\d{4,}\b/, "<ID>")
      msg = msg.gsub(/#<\w+:0x[0-9a-f]+>/i, "#<Object>")
      msg.strip
    end

    def lazy_cleanup!(now)
      cutoff = now - 3600
      @entries.delete_if { |_, e| e.last_sent_at < cutoff }
    end
  end
end
