defmodule Slack.Bot do
  @moduledoc """
  Process that owns a bot's RTM WebSocket connection.

  `Slack.Bot` is the runtime counterpart to the `Slack` behaviour: it opens the
  WebSocket, decodes inbound frames, folds them into a `Slack.State`, and
  dispatches each event to the user-supplied `bot_handler` module's callbacks.

  ## Lifecycle

  `start_link/4` performs three steps:

  1. Hits Slack's `rtm.start` endpoint to fetch a one-shot WebSocket URL plus
     the bot's initial team/identity payload. The module that performs this
     can be overridden via `config :slack, :rtm_module, …` for tests.
  2. Spawns a `Slack.WebSocketClient` pointed at that URL with `Slack.Bot`
     itself as the callback module.
  3. Each inbound text frame is JSON-decoded, atomised, run through
     `Slack.State.update/2`, and forwarded to the user module's
     `handle_event/3`.

  You generally won't call this module's callbacks directly — they implement the
  `Slack.WebSocketClient` behaviour and exist to glue the socket to your bot.
  """

  require Logger

  @behaviour Slack.WebSocketClient

  @doc """
  Connects to Slack and delegates events to `bot_handler`.

  ## Arguments

    * `bot_handler` — module implementing the `Slack` behaviour (typically a
      module that does `use Slack`).
    * `initial_state` — opaque value handed to the first callback invocation
      as the `state` argument. Threaded through callbacks from then on.
    * `token` — the Slack API token for this bot.
    * `options` — map of optional settings (see below).

  ## Options

    * `:keepalive` — milliseconds between WebSocket keepalive pings. Defaults
      to `10_000`.
    * `:name` — registers the spawned process under the given atom via
      `Process.register/2`. Defaults to `nil` (unregistered).
    * `:client` — module that backs the WebSocket transport. Must implement
      `start_link/4` and `cast/2`. Defaults to `Slack.WebSocketClient`;
      tests swap in a stub.

  ## Return values

  Returns `{:ok, pid}` on a successful RTM handshake, or `{:error, reason}` on
  failure. Known reasons include:

    * `"Timed out while connecting to the Slack RTM API"`
    * `"Could not connect to the Slack RTM API"` — DNS resolution failed
    * `"Sent too many connection requests at once to the Slack RTM API."` —
      Slack has rate-limited the `rtm.start` endpoint
    * any other error returned by the underlying HTTP client

  ## Examples

      {:ok, pid} = Slack.Bot.start_link(MyBot, [], "xoxb-…", %{name: :my_bot})

      :sys.get_state(:my_bot)

  """
  def start_link(bot_handler, initial_state, token, options \\ %{}) do
    options =
      Map.merge(
        %{
          client: Slack.WebSocketClient,
          keepalive: 10_000,
          name: nil
        },
        Map.new(options)
      )

    rtm_module = Application.get_env(:slack, :rtm_module, Slack.Rtm)

    case rtm_module.start(token) do
      {:ok, rtm} ->
        state = %{
          bot_handler: bot_handler,
          rtm: rtm,
          client: options.client,
          token: token,
          initial_state: initial_state
        }

        {:ok, pid} =
          options.client.start_link(state.rtm.url, __MODULE__, state,
            keepalive: options.keepalive
          )

        if options.name != nil do
          Process.register(pid, options.name)
        end

        {:ok, pid}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "Timed out while connecting to the Slack RTM API"}

      {:error, %Req.TransportError{reason: :nxdomain}} ->
        {:error, "Could not connect to the Slack RTM API"}

      {:error, %Slack.JsonDecodeError{string: "You are sending too many requests. Please relax."}} ->
        {:error, "Sent too many connection requests at once to the Slack RTM API."}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  @deprecated """
  `rtm.start` is replaced with `rtm.connect` and will no longer receive bots, channels, groups, users, or IMs.
  In future versions these will no longer be provided on initialization.
  """
  def init(%{
        bot_handler: bot_handler,
        rtm: rtm,
        client: client,
        token: token,
        initial_state: initial_state
      }) do
    slack = %Slack.State{
      process: self(),
      client: client,
      token: token,
      me: rtm.self,
      team: rtm.team
    }

    {:reconnect, %{slack: slack, bot_handler: bot_handler, process_state: initial_state}}
  end

  @doc false
  def onconnect(
        _websocket_request,
        %{slack: slack, process_state: process_state, bot_handler: bot_handler} = state
      ) do
    {:ok, new_process_state} = bot_handler.handle_connect(slack, process_state)
    {:ok, %{state | process_state: new_process_state}}
  end

  @doc false
  def ondisconnect({:error, :keepalive_timeout}, state) do
    {:reconnect, state}
  end

  def ondisconnect(
        reason,
        %{slack: slack, process_state: process_state, bot_handler: bot_handler} = state
      ) do
    try do
      bot_handler.handle_close(reason, slack, process_state)
      {:close, reason, state}
    rescue
      e -> log_and_reraise(e, __STACKTRACE__)
    end
  end

  @doc false
  def websocket_info(
        message,
        _connection,
        %{slack: slack, process_state: process_state, bot_handler: bot_handler} = state
      ) do
    try do
      {:ok, new_process_state} = bot_handler.handle_info(message, slack, process_state)
      {:ok, %{state | process_state: new_process_state}}
    rescue
      e -> log_and_reraise(e, __STACKTRACE__)
    end
  end

  @doc false
  def websocket_terminate(_reason, _conn, _state), do: :ok

  @doc false
  def websocket_handle(
        {:text, message},
        _conn,
        %{slack: slack, process_state: process_state, bot_handler: bot_handler} = state
      ) do
    message = prepare_message(message)

    updated_slack =
      if Map.has_key?(message, :type) do
        Slack.State.update(message, slack)
      else
        slack
      end

    new_process_state =
      if Map.has_key?(message, :type) do
        try do
          {:ok, new_process_state} = bot_handler.handle_event(message, slack, process_state)
          new_process_state
        rescue
          e -> log_and_reraise(e, __STACKTRACE__)
        end
      else
        process_state
      end

    {:ok, %{state | slack: updated_slack, process_state: new_process_state}}
  end

  def websocket_handle(_, _conn, state), do: {:ok, state}

  defp prepare_message(binstring) do
    binstring
    |> :binary.split(<<0>>)
    |> List.first()
    |> JSON.decode!()
    |> Slack.JSON.atomize_keys()
  end

  defp log_and_reraise(e, stacktrace) do
    Logger.error(Exception.format(:error, e, stacktrace))
    reraise e, stacktrace
  end
end
