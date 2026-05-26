defmodule Slack.Sends do
  @moduledoc """
  Helpers for writing frames back through an open RTM WebSocket.

  These functions are imported into any module that does `use Slack`, so
  inside a bot callback you can write `send_message("hi", channel, slack)`
  directly. They serialise messages to JSON and cast them onto the WebSocket
  process referenced by the `Slack.State` you pass in — so they require an
  active RTM connection.

  For richer messages (attachments, blocks, files, ephemeral posts), use the
  generated Web API modules (`Slack.Web.Chat`, `Slack.Web.Files`, etc.)
  instead — `send_message/3` covers only plain text.
  """

  alias Slack.Lookups

  @type slack :: Slack.State.t() | %{process: pid(), client: module()}
  @type channel :: String.t()

  @doc """
  Sends `text` to `channel` over the RTM WebSocket held by `slack`.

  `channel` may be:

    * a channel name prefixed with `#` (e.g. `"#general"`) — resolved via
      `Slack.Lookups.lookup_channel_id/2`
    * a user ID starting with `U` or `W` — the message is sent to the open
      DM channel for that user, opening one via `im.open` if necessary
    * a user reference starting with `@` (deprecated; see
      [Slack's changelog](https://api.slack.com/changelog/2017-09-the-one-about-usernames))
    * any channel ID that Slack accepts directly (`"C…"`, `"G…"`, `"D…"`)

  Raises `ArgumentError` if `#CHANNEL_NAME` cannot be resolved against the
  current state.
  """
  @spec send_message(String.t(), channel, slack) :: :ok
  def send_message(text, "#" <> channel_name = channel, slack) do
    channel_id = Lookups.lookup_channel_id(channel, slack)

    if channel_id do
      send_message(text, channel_id, slack)
    else
      raise ArgumentError, "channel ##{channel_name} not found"
    end
  end

  def send_message(text, "U" <> _user_id = user_id, slack) do
    send_message_to_user(text, user_id, slack)
  end

  def send_message(text, "W" <> _user_id = user_id, slack) do
    send_message_to_user(text, user_id, slack)
  end

  def send_message(text, "@" <> _user_name = user, slack) do
    user_id = Lookups.lookup_user_id(user, slack)
    send_message(text, user_id, slack)
  end

  def send_message(text, channel, slack) do
    %{
      type: "message",
      text: text,
      channel: channel
    }
    |> JSON.encode!()
    |> send_raw(slack)
  end

  @doc """
  Same as `send_message/3`, but threads the message under an existing parent.

  `thread` is the `ts` of the message you want to reply to — use the
  top-level parent's `ts`, not a nested reply's. RTM threaded replies are
  always posted, never broadcast back to the channel; for `reply_broadcast`
  support, use the Web API (`Slack.Web.Chat`).
  """
  @spec send_message(String.t(), channel, slack, String.t()) :: :ok
  def send_message(text, "#" <> channel_name = channel, slack, thread) do
    channel_id = Lookups.lookup_channel_id(channel, slack)

    if channel_id do
      send_message(text, channel_id, slack, thread)
    else
      raise ArgumentError, "channel ##{channel_name} not found"
    end
  end

  def send_message(text, channel, slack, thread) do
    %{
      type: "message",
      text: text,
      channel: channel,
      thread_ts: thread
    }
    |> JSON.encode!()
    |> send_raw(slack)
  end

  @doc """
  Notifies Slack that the bot is typing in `channel`.

  Slack clients render the "@bot is typing…" indicator for a few seconds
  after this is called. There is no acknowledgement.
  """
  @spec indicate_typing(channel, slack) :: :ok
  def indicate_typing(channel, slack) do
    %{
      type: "typing",
      channel: channel
    }
    |> JSON.encode!()
    |> send_raw(slack)
  end

  @doc """
  Sends a `ping` frame, optionally merging extra fields into the payload.

  Slack replies with a matching `pong`. The default `Slack.WebSocketClient`
  already issues low-level WebSocket keepalive pings; this is the
  application-level RTM ping, useful when you want to round-trip a custom
  payload such as a request id.
  """
  @spec send_ping(map() | keyword(), slack) :: :ok
  def send_ping(data \\ %{}, slack) do
    %{
      type: "ping"
    }
    |> Map.merge(Map.new(data))
    |> JSON.encode!()
    |> send_raw(slack)
  end

  @doc """
  Subscribes to `presence_change` events for `ids`.

  Slack's RTM no longer broadcasts presence updates by default — callers
  must opt-in per user. Pass a list of user IDs to start receiving events;
  pass `[]` to clear the subscription.
  """
  @spec subscribe_presence([String.t()], slack) :: :ok
  def subscribe_presence(ids \\ [], slack) do
    %{
      type: "presence_sub",
      ids: ids
    }
    |> JSON.encode!()
    |> send_raw(slack)
  end

  @doc """
  Casts an already-encoded JSON string onto the RTM WebSocket.

  Escape hatch for RTM event types `Slack.Sends` doesn't wrap directly. The
  string must be a complete, well-formed JSON message — Slack will close the
  connection on malformed frames.
  """
  @spec send_raw(String.t(), slack) :: :ok
  def send_raw(json, %{process: pid, client: client}) do
    client.cast(pid, {:text, json})
  end

  defp send_message_to_user(text, user_id, slack) do
    direct_message_id = Lookups.lookup_direct_message_id(user_id, slack)

    if direct_message_id do
      send_message(text, direct_message_id, slack)
    else
      open_im_channel(
        slack.token,
        user_id,
        fn id -> send_message(text, id, slack) end,
        fn reason -> reason end
      )
    end
  end

  defp open_im_channel(token, user_id, on_success, on_error) do
    url = Application.get_env(:slack, :url, "https://slack.com") <> "/api/im.open"
    options = Application.get_env(:slack, :web_http_client_opts, [])
    options = Keyword.merge(options, form: [token: token, user: user_id], decode_body: false)

    case Req.post(url, options) do
      {:ok, response} ->
        case response.body |> JSON.decode!() |> Slack.JSON.atomize_keys() do
          %{ok: true, channel: %{id: id}} -> on_success.(id)
          e = %{error: _error_message} -> on_error.(e)
        end

      {:error, reason} ->
        on_error.(reason)
    end
  end
end
