# Changelog

## Next

- **Breaking:** Requires Elixir 1.18.
- **Breaking:** Replace `jason` with Elixir's built-in `JSON` module.
- Replace `httpoison` with `req` as the HTTP client.
- Replace `websocket_client` with `mint_web_socket`.
- Rewrite update slack api mix task to generate docs by scraping `docs.slack.dev` directly.
- Add `excoveralls` for test coverage reporting.
- Add `junit_formatter` for Codecov flake/failure-rate tracking.
- Internal cleanups: codebase modernization to Elixir 1.19.
- Add weekly cron workflow to regenerate Slack Web API docs.

## 0.24.0

- Dependency updates.
