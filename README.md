# tg_error_notifier

Gem for Rails error notifications to Telegram.

## What it catches
- Unhandled errors in Rack/Rails request cycle.
- Failed ActiveJob executions.

## Quick usage
```ruby
# Gemfile
gem "tg_error_notifier"
```

```ruby
# config/initializers/telegram_error_notifier.rb
Rails.application.configure do
  config.telegram_error_notifier.bot_token = ENV["TELEGRAM_BOT_TOKEN"]
  config.telegram_error_notifier.chat_id = ENV["TELEGRAM_ERRORS_CHAT_ID"]
  config.telegram_error_notifier.app_name = "my_app"
end
```

## Environment variables
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ERRORS_CHAT_ID`
- `TELEGRAM_ERRORS_APP_NAME` (optional)

## Telegram setup (bot, private channel/group, chat_id)

### 1. Create a bot and get token
1. Open Telegram and start chat with `@BotFather`.
2. Send `/newbot` and follow prompts (bot name + username ending with `bot`).
3. Copy the HTTP API token (looks like `123456:ABC...`) and save it as `TELEGRAM_BOT_TOKEN`.

### 2. Create a private channel or private group

#### Private channel
1. Telegram -> New Channel -> set as **Private**.
2. Open channel settings -> Administrators -> add your bot as admin.
3. Grant at least permission to post messages.

#### Private group (or supergroup)
1. Telegram -> New Group -> add at least one member.
2. Add your bot to the group.
3. Promote bot to admin if needed (recommended for reliability).
4. Keep group private (no public username).

### 3. Get `chat_id`

#### Method A (easy): `@userinfobot` / `@RawDataBot`
- Add bot `@userinfobot` (or `@RawDataBot`) into your target channel/group.
- Send any message there.
- Open the helper bot dialog and read chat id.
- For channels/supergroups it is usually negative and starts with `-100...`.
- Delete this bot from your channel.

#### Method B (official API): `getUpdates`
1. Send at least one message in target chat after adding your bot.
2. Open in browser:
   `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getUpdates`
3. Find `chat` object and copy `chat.id`.

Examples:
- Private channel/supergroup: `-1001234567890`
- Private group (old style): `-123456789`

### 4. Validate before using in Rails
- Ensure bot is present in the target chat.
- Ensure bot has permission to send messages.
- Put value into `TELEGRAM_ERRORS_CHAT_ID` and run a smoke test.

## Error grouping

Group identical errors to avoid flooding. When the same exception repeats within a time window, only the first message is sent — subsequent occurrences are suppressed and reported as a count in the next message.

```ruby
TgErrorNotifier.configure do |config|
  config.grouping_enabled = true
  config.grouping_window = 60 # seconds (default)
end
```

Errors are grouped by exception class + normalized message (IDs and UUIDs are replaced with placeholders for better deduplication).

## Forum topics (threads)

Automatically create a Telegram Forum topic (thread) per unique error type. Each error gets its own topic in a supergroup with Forum Topics enabled.

```ruby
TgErrorNotifier.configure do |config|
  config.topics_enabled = true
  config.topic_icon_color = 0xFB6F5F # red (default), optional
end
```

**Requirements:** The chat must be a supergroup with Forum Topics enabled. The bot must have `can_manage_topics` admin permission.

You can combine both features — errors will be grouped within their respective topics:

```ruby
TgErrorNotifier.configure do |config|
  config.grouping_enabled = true
  config.grouping_window = 60
  config.topics_enabled = true
end
```

## Manual notification
```ruby
begin
  do_work
rescue => e
  pp TgErrorNotifier.capture_exception(e)
  # or with extra context:
  TgErrorNotifier.capture_exception(
    e,
    source: "custom",
    context: { feature: "sync", user_id: current_user&.id }
  )
  raise
end
```

`capture_exception` returns a diagnostic hash, e.g.:
- `{ sent: true, status: :sent, code: 200 }`
- `{ sent: false, status: :skipped, reason: "missing_chat_id" }`
- `{ sent: false, status: :failed, reason: "telegram_api_error", code: 400, body: "..." }`

## Manual message
```ruby
TgErrorNotifier.capture_message(
  "Background sync started",
  level: :info,
  source: "custom",
  context: { feature: "sync", user_id: current_user&.id }
)
```

`capture_message` returns the same diagnostic hash format as `capture_exception`.
