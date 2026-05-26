# Changelog

# Next

- Replace `httpoison` with `req` as the HTTP client. The `:web_http_client_opts`
  config now accepts Req options instead of HTTPoison/hackney options.
- Add `excoveralls` for test coverage reporting.
- Replace `websocket_client` with `mint_web_socket`. Introduces a new
  `Slack.WebSocketClient` GenServer that wraps `Mint.WebSocket` and is used as
  the default websocket transport for `Slack.Bot`. The consumer API
  (`Slack.Bot.start_link/4` and the `handle_connect` / `handle_event` /
  `handle_close` / `handle_info` callbacks) is unchanged.

## 0.24.0

- Dependency updates.
