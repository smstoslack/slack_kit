# Changelog

# Next

- Replace `httpoison` with `req` as the HTTP client. The `:web_http_client_opts`
  config now accepts Req options instead of HTTPoison/hackney options.
- Add `excoveralls` for test coverage reporting.
- Add `junit_formatter` to emit JUnit XML to `cover/junit.xml` and upload it to
  Codecov Test Analytics for flake/failure-rate tracking.
- Replace `websocket_client` with `mint_web_socket`. Introduces a new
  `Slack.WebSocketClient` GenServer that wraps `Mint.WebSocket` and is used as
  the default websocket transport for `Slack.Bot`. The consumer API
  (`Slack.Bot.start_link/4` and the `handle_connect` / `handle_event` /
  `handle_close` / `handle_info` callbacks) is unchanged.
- Rewrite `lib/mix/tasks/update_slack_api.exs` to regenerate the per-method
  JSON docs in `lib/slack/web/docs/` by scraping `docs.slack.dev` directly.
  Run with `mix run lib/mix/tasks/update_slack_api.exs`. Replaces the previous
  task that pulled from the now-unmaintained `slackhq/slack-api-docs` repo.

## 0.24.0

- Dependency updates.
