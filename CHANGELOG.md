# Changelog

## Next

- **Breaking:** Replace `jason` with Elixir's built-in `JSON` module (requires Elixir 1.18+). Callers that pattern-matched on `Jason.DecodeError` or relied on `jason` being a direct dependency will need to update.
- Replace `httpoison` with `req` as the HTTP client.
- Replace `websocket_client` with `mint_web_socket`.
- Rewrite update slack api mix task to generate docs by scraping `docs.slack.dev` directly.
- Add `excoveralls` for test coverage reporting.
- Add `junit_formatter` for Codecov flake/failure-rate tracking.

## 0.24.0

- Dependency updates.
