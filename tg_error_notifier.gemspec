# frozen_string_literal: true

require_relative "lib/tg_error_notifier/version"

Gem::Specification.new do |spec|
  spec.name          = "tg_error_notifier"
  spec.version       = TgErrorNotifier::VERSION
  spec.authors       = ["Sergei Ustinov"]
  spec.email         = ["se.ustinov@gmail.com"]

  spec.summary       = "Rails error notifications to Telegram"
  spec.description   = "Catches Rails request and ActiveJob exceptions and sends detailed alerts to Telegram."
  spec.homepage      = "https://github.com/sergeyustinov/TgErrorNotifier"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/sergeyustinov/TgErrorNotifier/releases"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
end
