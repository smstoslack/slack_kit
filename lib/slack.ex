defmodule Slack do
  @moduledoc """
  Defines the behaviour for a Slack [Real Time Messaging] (RTM) bot.

  `use Slack` injects four overridable callbacks — `handle_connect/2`,
  `handle_event/3`, `handle_close/3`, `handle_info/3` — plus a default
  `child_spec/1` so the module can be supervised, and imports the helper
  functions in `Slack.Lookups` and `Slack.Sends`. `Slack.Bot.start_link/4`
  takes the resulting module, opens the WebSocket, and dispatches incoming
  events to it.

  ## Quick start

  Define your bot:

      defmodule MyBot do
        use Slack

        def handle_connect(slack, state) do
          IO.puts("Connected as @\#{slack.me.name} to \#{slack.team.name}")
          {:ok, state}
        end

        # Greet anyone who says "hi" in any channel the bot can see.
        def handle_event(%{type: "message", text: "hi"} = msg, slack, state) do
          send_message("Hello to you too!", msg.channel, slack)
          {:ok, state}
        end

        # Catch-all — Slack sends many event types; ignoring unknown ones keeps
        # the bot from crashing on each new flavour.
        def handle_event(_event, _slack, state), do: {:ok, state}
      end

  Start it under your supervision tree:

      children = [
        {MyBot, []}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Or, for ad-hoc use:

      {:ok, _pid} = Slack.Bot.start_link(MyBot, [], "xoxb-…")

  See [Token Generation Instructions](token_generation_instructions.html) for
  obtaining a token.

  ## Callbacks

  All four callbacks are optional; the default implementations ignore their
  input and return the unchanged state.

  | Callback                          | When it fires                                                              |
  | --------------------------------- | -------------------------------------------------------------------------- |
  | `handle_connect(slack, state)`    | The WebSocket has connected and the bot identity is known.                 |
  | `handle_event(event, slack, state)` | An RTM event arrived from Slack. `event` is an atom-keyed map.            |
  | `handle_close(reason, slack, state)` | The WebSocket closed — return `:close` to stop, or `{:reconnect, state}`. |
  | `handle_info(msg, slack, state)`  | An arbitrary Erlang message arrived in the bot's mailbox.                  |

  Each callback returns `{:ok, state}` (with the exception of `handle_close/3`
  which may also return `:close`). The returned state is threaded into the
  next callback invocation, so you can carry arbitrary bot state across events.

  ## The `slack` argument

  Every callback receives a `Slack.State` struct that tracks the live view of
  the workspace. SlackKit folds each incoming RTM event into it before invoking
  your callback, so `slack.channels`, `slack.users`, and friends always reflect
  the latest known state. See `Slack.State` for the field layout.

  ## Sending messages

  Inside a callback, `send_message/3` (imported from `Slack.Sends`) writes a
  text message back through the WebSocket:

      send_message("Hello!", "C123ABC", slack)

  For richer messages — attachments, blocks, threads, ephemeral posts — use
  the corresponding Web API function under `Slack.Web.Chat`.

  ## Driving the bot from outside

  Anything sent to the bot's process arrives in `handle_info/3`, which is the
  natural entry point for "send this message from elsewhere in my app":

      def handle_info({:say, text, channel}, slack, state) do
        send_message(text, channel, slack)
        {:ok, state}
      end

      # …then, from a controller, a job, IEx, etc.
      send(bot_pid, {:say, "External hello", "#general"})

  [Real Time Messaging]: https://api.slack.com/rtm
  """

  defmacro __using__(_) do
    quote do
      import Slack
      import Slack.Lookups
      import Slack.Sends

      def handle_connect(_slack, state), do: {:ok, state}
      def handle_event(_message, _slack, state), do: {:ok, state}
      def handle_close(_reason, _slack, state), do: :close
      def handle_info(_message, _slack, state), do: {:ok, state}

      def child_spec(_opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end

      defoverridable handle_connect: 2,
                     handle_event: 3,
                     handle_close: 3,
                     handle_info: 3,
                     child_spec: 1
    end
  end
end
