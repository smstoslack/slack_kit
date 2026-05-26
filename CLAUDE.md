# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `mix deps.get` — fetch dependencies
- `mix test` — run the full ExUnit suite (includes `test/integration` which boots a Cowboy-backed fake Slack server)
- `mix test test/slack/state_test.exs` — run one file; append `:LINE` to run a single test
- `mix coveralls` / `mix coveralls.html` / `mix coveralls.json` — coverage (configured in `mix.exs` under `cli/0`)
- `mix format` and `mix credo` — both gate CI in [.github/workflows/lint.yaml](.github/workflows/lint.yaml); run before pushing
- `mix run lib/mix/tasks/update_slack_api.exs [method ...]` — regenerate the JSON in [priv/docs/methods/](priv/docs/methods/) by scraping docs.slack.dev. See [.claude/skills/generate-slack-docs/SKILL.md](.claude/skills/generate-slack-docs/SKILL.md).

CI matrix is Elixir 1.18 (OTP 26/27) and 1.19 (OTP 28); `mix.exs` requires `~> 1.18`.

## Architecture

### RTM bot pipeline

A user bot module does `use Slack` ([lib/slack.ex](lib/slack.ex)) to get default `handle_connect/2`, `handle_event/3`, `handle_close/3`, `handle_info/3` callbacks plus imports of `Slack.Lookups` and `Slack.Sends`.

`Slack.Bot.start_link/4` ([lib/slack/bot.ex](lib/slack/bot.ex)) is the entrypoint. It:

1. Calls `Slack.Rtm.start/1` (overridable via `config :slack, :rtm_module, ...` — important for tests) which hits `rtm.start` over HTTP via Req and returns the websocket URL plus initial team/self payload.
2. Starts a `Slack.WebSocketClient` process pointed at that URL with `Slack.Bot` itself as the callback module.
3. `Slack.Bot` implements the `Slack.WebSocketClient` behaviour, decodes each incoming text frame into atom-keyed maps, runs `Slack.State.update/2` to fold the RTM event into the long-lived `%Slack.State{}`, and then invokes the user module's `handle_event/3`.

`Slack.State` ([lib/slack/state.ex](lib/slack/state.ex)) is pattern-matched per RTM event type — adding support for a new event type means adding another `update/2` clause there. The struct also implements `Access` so callers can use `get_in`/`put_in`.

`Slack.Sends.send_raw/2` ([lib/slack/sends.ex](lib/slack/sends.ex)) routes outbound frames through `client.cast(pid, {:text, json})`. The `client` is whatever module was injected at bot startup (defaults to `Slack.WebSocketClient`); tests swap in a fake.

### WebSocketClient compatibility shim

[lib/slack/web_socket_client.ex](lib/slack/web_socket_client.ex) is a `GenServer` built on `Mint.WebSocket` that deliberately mirrors the Erlang `:websocket_client` API (`init/1`, `onconnect/2`, `ondisconnect/2`, `websocket_handle/3`, `websocket_info/3`, `websocket_terminate/3`, plus `start_link/4` and `cast/2`). This is a drop-in replacement after migrating off `websocket_client`; preserve the contract when editing — `Slack.Bot` and the fake test client both rely on it.

### Web API — metaprogrammed from JSON

[lib/slack/web/web.ex](lib/slack/web/web.ex) reads every file in [priv/docs/methods/](priv/docs/methods/) at compile time and generates a module/function per Slack endpoint (e.g. `chat.postMessage.json` → `Slack.Web.Chat.post_message/N`). Required JSON args become positional function arguments; everything else goes through an `optional_params` map.

Implications:

- **Never hand-edit files in `priv/docs/methods/`.** Regenerate them with the mix task above.
- Adding/changing a Web API surface = changing the JSON or the codegen in `web.ex`/`documentation.ex`, not writing per-method modules.
- HTTP transport is pluggable: `config :slack, :web_http_client, MyClient` swaps the whole client (must implement `Slack.Web.Client.post!/2`); `config :slack, :web_http_client_opts, [...]` passes Req options to the default client only.

### Test infrastructure

Integration tests (`test/integration/*`) spin up `Slack.FakeSlack` ([test/support/fake_slack.ex](test/support/fake_slack.ex)) — a Plug.Cowboy server on port 51345 that serves a fake `rtm.start` response and a websocket endpoint. They work by setting `config :slack, :url, "http://localhost:51345"` so all of `Slack.Rtm`, `Slack.Web`, and `Slack.Sends` get redirected. `test/support/` is compiled only in `:test` (`elixirc_paths/1` in [mix.exs](mix.exs)).

### Runtime configuration keys (`:slack` app env)

- `:api_token` — default token for Web API calls when `optional_params` doesn't carry one
- `:url` — base URL (overridden in integration tests)
- `:web_http_client` / `:web_http_client_opts` — see above
- `:rtm_module` — swap `Slack.Rtm` for tests
