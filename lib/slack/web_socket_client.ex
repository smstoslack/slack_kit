defmodule Slack.WebSocketClient do
  @moduledoc """
  A small WebSocket client process built on top of `Mint.WebSocket`.

  The public surface intentionally mirrors the Erlang `:websocket_client`
  library so that `Slack.Bot` (and any test stubs that follow the same
  contract) can use it as a drop-in replacement:

      Slack.WebSocketClient.start_link(url, callback_module, state, opts)
      Slack.WebSocketClient.cast(pid, {:text, "..."})

  Callback modules implement the `Slack.WebSocketClient` behaviour, which
  re-uses the function names from `:websocket_client`:

    * `init/1`
    * `onconnect/2`
    * `ondisconnect/2`
    * `websocket_handle/3`
    * `websocket_info/3`
    * `websocket_terminate/3`
  """

  use GenServer

  alias Mint.HTTP
  alias Mint.WebSocket

  require Logger

  @type frame ::
          {:text, binary}
          | {:binary, binary}
          | :ping
          | {:ping, binary}
          | :pong
          | {:pong, binary}
          | :close
          | {:close, non_neg_integer, binary}

  @type handler_response ::
          {:ok, any}
          | {:reply, frame, any}
          | {:close, any, any}

  @callback init(any) :: {:ok, any} | {:once, any} | {:reconnect, any}
  @callback onconnect(any, any) :: {:ok, any}
  @callback ondisconnect(any, any) ::
              {:ok, any} | {:reconnect, any} | {:close, any, any}
  @callback websocket_handle(frame, any, any) :: handler_response
  @callback websocket_info(any, any, any) :: handler_response
  @callback websocket_terminate(any, any, any) :: :ok

  @doc """
  Starts the WebSocket client and connects to `url`.

  `url` may be a string or charlist (the latter is accepted for compatibility
  with the older `:websocket_client` callers).

  ## Options

    * `:keepalive` - how often (in ms) to send a keepalive ping. Defaults to
      `:infinity` (no keepalive).
  """
  def start_link(url, module, state, opts \\ []) do
    GenServer.start_link(__MODULE__, {url, module, state, opts})
  end

  @doc """
  Sends a frame on the WebSocket. Mirrors `:websocket_client.cast/2`.
  """
  def cast(pid, frame) do
    GenServer.cast(pid, {:send, frame})
  end

  @impl true
  def init({url, module, state, opts}) do
    keepalive = Keyword.get(opts, :keepalive, :infinity)

    case module.init(state) do
      {tag, handler_state} when tag in [:ok, :reconnect, :once] ->
        reconnect? = tag != :once

        data = %{
          url: parse_url(url),
          module: module,
          handler_state: handler_state,
          keepalive: keepalive,
          keepalive_timer: nil,
          reconnect?: reconnect?,
          conn: nil,
          websocket: nil,
          request_ref: nil,
          upgrade_status: nil,
          upgrade_headers: nil
        }

        {:ok, data, {:continue, :connect}}

      other ->
        {:stop, {:bad_init, other}}
    end
  end

  @impl true
  def handle_continue(:connect, data) do
    case connect(data) do
      {:ok, data} -> {:noreply, data}
      {:error, reason} -> handle_disconnect(reason, data)
    end
  end

  @impl true
  def handle_cast({:send, frame}, %{websocket: nil} = data) do
    Logger.warning("Slack.WebSocketClient dropping frame, not connected: #{inspect(frame)}")

    {:noreply, data}
  end

  def handle_cast({:send, frame}, data) do
    case send_frame(data, frame) do
      {:ok, data} -> {:noreply, data}
      {:error, data, reason} -> handle_disconnect(reason, data)
    end
  end

  @impl true
  def handle_info(:keepalive, %{websocket: nil} = data), do: {:noreply, data}

  def handle_info(:keepalive, data) do
    case send_frame(data, :ping) do
      {:ok, data} -> {:noreply, schedule_keepalive(data)}
      {:error, data, reason} -> handle_disconnect(reason, data)
    end
  end

  def handle_info(message, %{conn: conn} = data) when conn != nil do
    case WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        data = %{data | conn: conn}
        handle_responses(responses, data)

      {:error, conn, reason, _responses} ->
        handle_disconnect(reason, %{data | conn: conn})

      :unknown ->
        dispatch_info(message, data)
    end
  end

  def handle_info(message, data), do: dispatch_info(message, data)

  @impl true
  def terminate(reason, %{module: module, handler_state: handler_state} = data) do
    close_connection(data)
    module.websocket_terminate(reason, nil, handler_state)
    :ok
  end

  def terminate(_reason, _data), do: :ok

  defp connect(data) do
    %{url: %{scheme: scheme, host: host, port: port, path: path}} = data

    http_scheme = if scheme == :wss, do: :https, else: :http
    connect_opts = connect_opts(http_scheme)

    with {:ok, conn} <- HTTP.connect(http_scheme, host, port, connect_opts),
         {:ok, conn, ref} <- WebSocket.upgrade(scheme, conn, path, []) do
      {:ok, %{data | conn: conn, request_ref: ref}}
    else
      {:error, reason} -> {:error, reason}
      {:error, _conn, reason} -> {:error, reason}
    end
  end

  defp connect_opts(:https), do: [transport_opts: [cacerts: cacerts()]]
  defp connect_opts(:http), do: []

  defp cacerts, do: :public_key.cacerts_get()

  defp handle_responses([], data), do: {:noreply, data}

  defp handle_responses([{:status, ref, status} | rest], %{request_ref: ref} = data) do
    handle_responses(rest, %{data | upgrade_status: status})
  end

  defp handle_responses([{:headers, ref, headers} | rest], %{request_ref: ref} = data) do
    handle_responses(rest, %{data | upgrade_headers: headers})
  end

  defp handle_responses([{:done, ref} | rest], %{request_ref: ref} = data) do
    case WebSocket.new(data.conn, ref, data.upgrade_status, data.upgrade_headers) do
      {:ok, conn, websocket} ->
        data = %{data | conn: conn, websocket: websocket}

        case data.module.onconnect(ref, data.handler_state) do
          {:ok, handler_state} ->
            data =
              %{data | handler_state: handler_state}
              |> schedule_keepalive()

            handle_responses(rest, data)
        end

      {:error, conn, reason} ->
        handle_disconnect(reason, %{data | conn: conn})
    end
  end

  defp handle_responses([{:data, ref, payload} | rest], %{request_ref: ref} = data) do
    {:ok, websocket, frames} = WebSocket.decode(data.websocket, payload)
    data = %{data | websocket: websocket}

    case dispatch_frames(frames, data) do
      {:ok, data} -> handle_responses(rest, data)
      {:disconnect, reason, data} -> handle_disconnect(reason, data)
    end
  end

  defp dispatch_frames([], data), do: {:ok, data}

  defp dispatch_frames([frame | rest], data) do
    case handle_incoming_frame(frame, data) do
      {:ok, data} -> dispatch_frames(rest, data)
      {:disconnect, reason, data} -> {:disconnect, reason, data}
    end
  end

  defp handle_incoming_frame({:ping, payload}, data) do
    case send_frame(data, {:pong, payload}) do
      {:ok, data} -> {:ok, data}
      {:error, data, reason} -> {:disconnect, reason, data}
    end
  end

  defp handle_incoming_frame({:close, _code, _reason} = frame, data) do
    dispatch_close(frame, data)
  end

  defp handle_incoming_frame(frame, data) do
    args = [frame, data.request_ref, data.handler_state]
    invoke_handler(:websocket_handle, args, data)
  end

  defp dispatch_close(frame, data) do
    args = [frame, data.request_ref, data.handler_state]

    case invoke_handler(:websocket_handle, args, data) do
      {:ok, data} -> {:disconnect, :remote, data}
      {:disconnect, _reason, data} -> {:disconnect, :remote, data}
    end
  end

  defp dispatch_info(message, data) do
    args = [message, data.request_ref, data.handler_state]

    case invoke_handler(:websocket_info, args, data) do
      {:ok, data} -> {:noreply, data}
      {:disconnect, reason, data} -> handle_disconnect(reason, data)
    end
  end

  defp invoke_handler(callback, args, data) do
    data.module
    |> apply(callback, args)
    |> handle_callback_result(data)
  end

  defp handle_callback_result(:ok, data), do: {:ok, data}

  defp handle_callback_result({:ok, handler_state}, data) do
    {:ok, %{data | handler_state: handler_state}}
  end

  defp handle_callback_result({:reply, frame, handler_state}, data) do
    data = %{data | handler_state: handler_state}

    case send_frame(data, frame) do
      {:ok, data} -> {:ok, data}
      {:error, data, reason} -> {:disconnect, reason, data}
    end
  end

  defp handle_callback_result({:close, reason, handler_state}, data) do
    {:disconnect, reason, %{data | handler_state: handler_state}}
  end

  defp send_frame(data, frame) do
    case WebSocket.encode(data.websocket, frame) do
      {:ok, websocket, payload} ->
        data = %{data | websocket: websocket}

        case WebSocket.stream_request_body(data.conn, data.request_ref, payload) do
          {:ok, conn} -> {:ok, %{data | conn: conn}}
          {:error, conn, reason} -> {:error, %{data | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{data | websocket: websocket}, reason}
    end
  end

  defp handle_disconnect(reason, data) do
    data = cancel_keepalive(data)
    close_connection(data)

    case data.module.ondisconnect(reason, data.handler_state) do
      {:ok, handler_state} ->
        data = reset_connection(%{data | handler_state: handler_state})
        {:stop, :normal, data}

      {:reconnect, handler_state} ->
        data = reset_connection(%{data | handler_state: handler_state})
        {:noreply, data, {:continue, :connect}}

      {:close, close_reason, handler_state} ->
        data = reset_connection(%{data | handler_state: handler_state})
        {:stop, normalize_stop(close_reason), data}
    end
  end

  defp reset_connection(data) do
    %{
      data
      | conn: nil,
        websocket: nil,
        request_ref: nil,
        upgrade_status: nil,
        upgrade_headers: nil
    }
  end

  defp close_connection(%{conn: nil}), do: :ok

  defp close_connection(%{conn: conn}) do
    _ = HTTP.close(conn)
    :ok
  end

  defp schedule_keepalive(%{keepalive: :infinity} = data), do: data

  defp schedule_keepalive(data) do
    data = cancel_keepalive(data)
    timer = Process.send_after(self(), :keepalive, data.keepalive)
    %{data | keepalive_timer: timer}
  end

  defp cancel_keepalive(%{keepalive_timer: nil} = data), do: data

  defp cancel_keepalive(%{keepalive_timer: timer} = data) do
    Process.cancel_timer(timer)
    %{data | keepalive_timer: nil}
  end

  defp parse_url(url) when is_list(url), do: parse_url(List.to_string(url))

  defp parse_url(url) when is_binary(url) do
    uri = URI.parse(url)

    scheme =
      case uri.scheme do
        "wss" -> :wss
        "https" -> :wss
        "ws" -> :ws
        "http" -> :ws
        _ -> :ws
      end

    path = build_path(uri)

    %{scheme: scheme, host: uri.host, port: uri.port, path: path}
  end

  defp build_path(%URI{path: nil, query: nil}), do: "/"
  defp build_path(%URI{path: path, query: nil}), do: path || "/"
  defp build_path(%URI{path: path, query: query}), do: (path || "/") <> "?" <> query

  defp normalize_stop(:normal), do: :normal
  defp normalize_stop(:shutdown), do: :shutdown
  defp normalize_stop({:shutdown, _} = reason), do: reason
  defp normalize_stop(other), do: {:shutdown, other}
end
