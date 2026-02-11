# frozen_string_literal: true

module TgErrorNotifier
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue StandardError => e
      TgErrorNotifier.notify(
        exception: e,
        source: "rack",
        context: {
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          query: env["QUERY_STRING"],
          request_id: env["action_dispatch.request_id"]
        }
      )
      raise
    end
  end
end
