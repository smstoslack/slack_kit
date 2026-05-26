# Configuration

SlackKit reads runtime configuration from the `:slack` application environment.
All keys are optional unless noted otherwise; sensible defaults are provided.

```elixir
import Config

config :slack,
  api_token: System.get_env("SLACK_TOKEN"),
  url: "https://slack.com",
  web_http_client: Slack.Web.DefaultClient,
  web_http_client_opts: [receive_timeout: 10_000]
```

## Keys

### `:api_token`

The default token used for Web API calls when an `optional_params` map does not
carry its own `:token`. Every generated function in `Slack.Web.*` falls back to
this value. RTM bots receive their token through
`Slack.Bot.start_link/4` instead and do not consult this key.

```elixir
config :slack, api_token: "xoxb-…"
```

See the [Token Generation Instructions](token_generation_instructions.html) for
how to obtain a token.

### `:url`

Base URL for Slack's HTTP and RTM endpoints. Defaults to `"https://slack.com"`.
Override this in tests to point at a local fake server:

```elixir
config :slack, url: "http://localhost:51345"
```

This redirects `rtm.start`, every `Slack.Web.*` call, and `Slack.Sends`' direct
message helper through the same base, which makes it possible to run a full
bot against a stub server.

### `:web_http_client`

Module that performs Web API HTTP calls. Must implement the `Slack.Web.Client`
behaviour. Defaults to `Slack.Web.DefaultClient`. Use this when you need to
inject auth headers, add retries, wrap responses, or send requests through a
proxy.

```elixir
config :slack, web_http_client: MyApp.SlackClient
```

### `:web_http_client_opts`

Keyword list of options passed straight through to `Req` by
`Slack.Web.DefaultClient`. Only consulted when the default client is in use;
custom clients are responsible for their own options.

```elixir
config :slack,
  web_http_client_opts: [
    connect_options: [timeout: 10_000],
    receive_timeout: 10_000
  ]
```

See [`Req.new/1`](https://hexdocs.pm/req/Req.html#new/1) for the full list of
options.

### `:rtm_module`

Module used to fetch the RTM WebSocket URL on bot startup. Defaults to the
internal Slack.Rtm. This is intended for tests — swap in a stub that returns
a fake `rtm.start` payload to avoid hitting the network. The module must
export a `start/1` function that takes a token and returns
`{:ok, %{url: …, self: …, team: …}}` on success or `{:error, reason}` on
failure.

```elixir
config :slack, :rtm_module, MyApp.FakeRtm
```

## Per-call token override

When you need to call the Web API with a different token than the configured
default — for example, a multi-tenant app that holds a token per workspace —
pass `:token` in `optional_params`:

```elixir
Slack.Web.Chat.post_message("C123", "hello", %{token: workspace.token})
```

The per-call token always takes precedence over `:api_token`.
