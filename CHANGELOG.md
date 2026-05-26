# Changelog

## Next

- Scrape per-method scopes and rate limits from `docs.slack.dev` and include them in the generated `Slack.Web.*` function docs (with links to the upstream scope and rate-limit reference pages).
- Extract the ~30 errors Slack lists on every Web API method into a new `Slack.Web.Errors` module. Per-method docs now only list errors specific to that method and link to `Slack.Web.Errors` for the shared set, dramatically reducing noise in the generated docs. The doc-regeneration mix task strips common errors on every run.

## v0.25.0-alpha.0

- **Breaking:** Requires Elixir 1.18.
- **Breaking:** Replace `jason` with Elixir's built-in `JSON` module.
- Replace `httpoison` with `req` as the HTTP client.
- Replace `websocket_client` with `mint_web_socket`.
- Rewrite update slack api mix task to generate docs by scraping `docs.slack.dev` directly.
- Add `excoveralls` for test coverage reporting.
- Add `junit_formatter` for Codecov flake/failure-rate tracking.
- Internal cleanups: codebase modernization to Elixir 1.19.
- Add weekly cron workflow to regenerate Slack Web API docs.
- Regenerate Slack Web API docs on 2026-05-25.

## v0.24.0

- Update dependencies to latest versions.
