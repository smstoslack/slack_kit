# SlackKit

[![hex.pm version](https://img.shields.io/hexpm/v/slack_kit?style=flat-square)](https://hex.pm/packages/slack_kit)
[![Build Status](https://img.shields.io/github/actions/workflow/status/smstoslack/slack_kit/ci.yaml?branch=main&style=flat-square)](https://github.com/smstoslack/slack_kit/actions/workflows/ci.yaml)
[![Coverage Status](https://img.shields.io/codecov/c/github/smstoslack/slack_kit?style=flat-square)](https://app.codecov.io/gh/smstoslack/slack_kit)
[![hex.pm downloads](https://img.shields.io/hexpm/dt/slack_kit?style=flat-square)](https://hex.pm/packages/slack_kit)

SlackKit is a Slack client for Elixir. It covers both halves of the Slack
platform from a single library:

- **Real-Time Messaging (RTM).** A long-lived WebSocket connection that
  streams workspace events (messages, presence changes, channel updates…) into
  a bot module of your choosing. See [`Slack`](Slack.html) and
  [`Slack.Bot`](Slack.Bot.html).
- **Web API.** The full Slack Web API surface — every `chat.postMessage`,
  `conversations.list`, `users.info`, and so on — generated at compile time
  from the official JSON schemas. See the `Slack.Web.*` modules.

You'll need a Slack API token, which can be obtained by following the
[Token Generation Instructions](token_generation_instructions.html) or by
creating a new [bot integration](https://my.slack.com/services/new/bot).

[Real time Messaging API]: https://api.slack.com/rtm

## Fork

SlackKit is a fork of [Elixir-Slack](https://github.com/BlakeWilliams/Elixir-Slack),
which is no longer maintained. It has been updated to use the latest versions
of dependencies and migrated off the unmaintained `websocket_client` Erlang
library onto `Mint.WebSocket`.

## Installation

Add `:slack_kit` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:slack_kit, "~> 0.24"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

## Real Time Messaging (RTM) Bot Usage

Define a module that uses the Slack behaviour and defines the appropriate
callback methods.

```elixir
defmodule SlackRtm do
  use Slack

  def handle_connect(slack, state) do
    IO.puts "Connected as #{slack.me.name}"
    {:ok, state}
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    send_message("I got a message!", message.channel, slack)
    {:ok, state}
  end
  def handle_event(_, _, state), do: {:ok, state}

  def handle_info({:message, text, channel}, slack, state) do
    IO.puts "Sending your message, captain!"

    send_message(text, channel, slack)

    {:ok, state}
  end
  def handle_info(_, _, state), do: {:ok, state}
end
```

To run this example, you'll want to call `Slack.Bot.start_link(SlackRtm, [],
"TOKEN_HERE")` and run the project with `mix run --no-halt`.

You can send messages to channels using `send_message/3` which takes the message
as the first argument, channel/user as the second, and the passed in `slack`
state as the third.

The passed-in `slack` argument is a `Slack.State` struct that's folded forward
as RTM events arrive. It exposes the current bot identity (`me`), team
(`team`), and live maps of `channels`, `groups`, `users`, `bots`, and `ims`
keyed by ID — see [`Slack.State`](Slack.State.html) for the full surface.

[rtm.connect]: https://docs.slack.dev/reference/methods/rtm.connect/

To trigger sends from outside the RTM loop — for example, from a Phoenix
controller or a periodic job — leverage `handle_info/3`:

```elixir
{:ok, rtm} = Slack.Bot.start_link(SlackRtm, [], "token")
send rtm, {:message, "External message", "#general"}
#=> {:message, "External message", "#general"}
#==> Sending your message, captain!
```

Slack has *a lot* of message types, so define a catch-all `handle_event/3`
clause to keep unrecognised events from crashing your bot. A full list of types
is on the [RTM API page].

[RTM API page]: https://api.slack.com/rtm

## Web API Usage

The complete Slack Web API surface is generated at compile time from the JSON
schemas under `lib/slack/web/docs/`. Each endpoint becomes a function on a
module derived from its name — for example `chat.postMessage` becomes
`Slack.Web.Chat.post_message`, and `conversations.list` becomes
`Slack.Web.Conversations.list`. Required parameters are positional; everything
else goes through an `optional_params` map.

There are two ways to authenticate. The common case is to set a default token in
application config:

```elixir
config :slack, api_token: "xoxb-…"
```

Alternatively, pass `%{token: "VALUE"}` in `optional_params` on any call. This
overrides the configured `:api_token` and is useful for multi-workspace apps.

Quick example — get every member's real name:

```elixir
"xoxb-…"
|> then(&Slack.Web.Users.list(%{token: &1}))
|> Map.fetch!("members")
|> Enum.map(& &1["real_name"])
```

### Configuration

```elixir
import Config

config :slack,
  api_token: System.get_env("SLACK_TOKEN"),
  url: "https://slack.com",
  web_http_client: Slack.Web.DefaultClient,
  web_http_client_opts: [receive_timeout: 10_000]
```

See [Configuration](configuration.html) for the full list of supported config
keys, including custom HTTP clients and `Req` options.

## Documentation

Full documentation, including all generated `Slack.Web.*` modules, lives at
[hexdocs.pm/slack_kit](https://hexdocs.pm/slack_kit/).

## Copyright and License

Copyright (c) 2026 Samuel Gordalina
Copyright (c) 2014-2022 Blake Williams

Source code is released under [the MIT license](./LICENSE.md).
