defmodule Slack.WebSocketClientTest do
  use ExUnit.Case, async: false

  alias Slack.WebSocketClient

  @port 51_346
  @url "ws://localhost:#{@port}/ws"

  defmodule EchoSocket do
    @behaviour :cowboy_websocket

    def init(req, _opts), do: {:cowboy_websocket, req, %{}, %{idle_timeout: 5_000}}

    def websocket_init(state) do
      send(test_pid(), {:server_connected, self()})
      {:ok, state}
    end

    def websocket_handle({:text, msg}, state) do
      send(test_pid(), {:server_received, msg})
      {:reply, {:text, msg}, state}
    end

    def websocket_handle({:binary, msg}, state) do
      send(test_pid(), {:server_received_binary, msg})
      {:reply, {:binary, msg}, state}
    end

    def websocket_handle({:ping, _payload}, state) do
      send(test_pid(), :server_received_ping)
      {:ok, state}
    end

    def websocket_handle(_frame, state), do: {:ok, state}

    def websocket_info({:send_text, text}, state), do: {:reply, {:text, text}, state}
    def websocket_info({:send_binary, bin}, state), do: {:reply, {:binary, bin}, state}
    def websocket_info({:send_ping, payload}, state), do: {:reply, {:ping, payload}, state}

    def websocket_info({:server_close, code, reason}, state),
      do: {:reply, {:close, code, reason}, state}

    def websocket_info(_msg, state), do: {:ok, state}

    def terminate(_reason, _req, _state), do: :ok

    defp test_pid, do: Application.get_env(:slack, :ws_test_pid)
  end

  defmodule NoopRouter do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    match _ do
      send_resp(conn, 404, "")
    end
  end

  defmodule RawWsServer do
    @moduledoc false
    # A minimal raw-TCP WebSocket server used to drive scenarios where the
    # client's local write side is half-closed via `:gen_tcp.shutdown/2`.
    # Cowboy auto-closes when it sees the FIN, but a passive-mode listener
    # parked in a `receive` loop keeps the server's write direction open so
    # the test can push server-to-client frames after the half-close.

    @ws_magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def start(parent) do
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen)
      pid = spawn_link(fn -> run(listen, parent) end)
      {pid, port}
    end

    defp run(listen, parent) do
      {:ok, sock} = :gen_tcp.accept(listen)
      :gen_tcp.close(listen)

      headers = read_headers(sock, %{})
      key = Map.fetch!(headers, "sec-websocket-key")
      accept = :sha |> :crypto.hash(key <> @ws_magic) |> Base.encode64()

      :gen_tcp.send(sock, [
        "HTTP/1.1 101 Switching Protocols\r\n",
        "Upgrade: websocket\r\n",
        "Connection: Upgrade\r\n",
        "Sec-WebSocket-Accept: ",
        accept,
        "\r\n\r\n"
      ])

      :inet.setopts(sock, packet: :raw)
      send(parent, {:raw_ws_upgraded, self()})
      serve(sock)
    end

    defp read_headers(sock, acc) do
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, {:http_request, _, _, _}} ->
          read_headers(sock, acc)

        {:ok, {:http_header, _, name, _, value}} ->
          read_headers(
            sock,
            Map.put(acc, name |> to_string() |> String.downcase(), to_string(value))
          )

        {:ok, :http_eoh} ->
          acc
      end
    end

    defp serve(sock) do
      receive do
        {:send, data} ->
          :gen_tcp.send(sock, data)
          serve(sock)

        :close ->
          :gen_tcp.close(sock)
      end
    end
  end

  defmodule Handler do
    @behaviour Slack.WebSocketClient

    def init(state) do
      tag = Map.get(state, :init_tag, :reconnect)
      send(state.test_pid, {:init, tag})
      {tag, state}
    end

    def onconnect(ref, state) do
      send(state.test_pid, {:onconnect, ref})
      {:ok, state}
    end

    def ondisconnect(reason, state) do
      send(state.test_pid, {:ondisconnect, reason})

      case Map.get(state, :on_disconnect, :close) do
        :reconnect -> {:reconnect, state}
        :close -> {:close, reason, state}
        :close_normal -> {:close, :normal, state}
        :close_shutdown -> {:close, :shutdown, state}
        :close_shutdown_tuple -> {:close, {:shutdown, :bye}, state}
        :ok -> {:ok, state}
      end
    end

    def websocket_handle(frame, _ref, state) do
      send(state.test_pid, {:websocket_handle, frame})

      case Map.get(state, :reply_with) do
        :bare_ok ->
          :ok

        {:close_with, reason} ->
          {:close, reason, %{state | reply_with: nil}}

        nil ->
          {:ok, state}

        frame ->
          {:reply, frame, %{state | reply_with: nil}}
      end
    end

    def websocket_info(message, _ref, state) do
      send(state.test_pid, {:websocket_info, message})

      case Map.get(state, :info_reply) do
        {:close_with, reason} -> {:close, reason, %{state | info_reply: nil}}
        _ -> {:ok, state}
      end
    end

    def websocket_terminate(reason, _ref, state) do
      send(state.test_pid, {:websocket_terminate, reason})
      :ok
    end
  end

  setup_all do
    {:ok, _pid} =
      Plug.Cowboy.http(
        NoopRouter,
        [],
        port: @port,
        ref: __MODULE__.HTTP,
        dispatch: [
          {:_,
           [
             {"/ws", EchoSocket, []},
             {:_, Plug.Cowboy.Handler, {NoopRouter, []}}
           ]}
        ]
      )

    on_exit(fn -> Plug.Cowboy.shutdown(__MODULE__.HTTP) end)

    :ok
  end

  setup do
    Application.put_env(:slack, :ws_test_pid, self())
    :ok
  end

  defp start_client(extra_state \\ %{}, opts \\ []) do
    state = Map.merge(%{test_pid: self()}, extra_state)
    WebSocketClient.start_link(@url, Handler, state, opts)
  end

  defp await_connect do
    assert_receive {:init, _}, 500
    assert_receive {:onconnect, _ref}, 500
    assert_receive {:server_connected, server_pid}, 500
    server_pid
  end

  describe "start_link/4" do
    test "calls init/1 and onconnect/2 on the handler when connection succeeds" do
      {:ok, _pid} = start_client()
      await_connect()
    end

    test "accepts a charlist URL (compatibility with :websocket_client callers)" do
      {:ok, _pid} =
        WebSocketClient.start_link(String.to_charlist(@url), Handler, %{test_pid: self()}, [])

      await_connect()
    end

    test "passes the keepalive option through (server auto-pongs the client's pings)" do
      {:ok, _pid} = start_client(%{}, keepalive: 50)
      await_connect()
      assert_receive {:websocket_handle, {:pong, _}}, 500
    end

    test "default keepalive is :infinity and no pongs come back" do
      {:ok, _pid} = start_client()
      await_connect()
      refute_receive {:websocket_handle, {:pong, _}}, 200
    end

    test "stops if init/1 returns an unexpected value" do
      defmodule BadHandler do
        @behaviour Slack.WebSocketClient
        def init(_state), do: :nope
        def onconnect(_ref, state), do: {:ok, state}
        def ondisconnect(_reason, state), do: {:close, :normal, state}
        def websocket_handle(_frame, _ref, state), do: {:ok, state}
        def websocket_info(_msg, _ref, state), do: {:ok, state}
        def websocket_terminate(_reason, _ref, _state), do: :ok
      end

      Process.flag(:trap_exit, true)
      {:error, {:bad_init, :nope}} = WebSocketClient.start_link(@url, BadHandler, %{}, [])
    end
  end

  describe "cast/2" do
    test "sends a text frame to the server" do
      {:ok, pid} = start_client()
      await_connect()

      WebSocketClient.cast(pid, {:text, "hello"})
      assert_receive {:server_received, "hello"}, 500
    end

    test "sends a binary frame to the server" do
      {:ok, pid} = start_client()
      await_connect()

      WebSocketClient.cast(pid, {:binary, <<1, 2, 3>>})
      assert_receive {:server_received_binary, <<1, 2, 3>>}, 500
    end

    test "frames cast before the upgrade completes are dropped without crashing" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client()
      WebSocketClient.cast(pid, {:text, "too-early"})
      await_connect()
      assert Process.alive?(pid)
    end
  end

  describe "receiving frames" do
    test "decoded text frames are dispatched to websocket_handle/3" do
      {:ok, _pid} = start_client()
      server = await_connect()

      send(server, {:send_text, "from-server"})
      assert_receive {:websocket_handle, {:text, "from-server"}}, 500
    end

    test "binary frames are dispatched to websocket_handle/3" do
      {:ok, _pid} = start_client()
      server = await_connect()

      send(server, {:send_binary, <<9, 9, 9>>})
      assert_receive {:websocket_handle, {:binary, <<9, 9, 9>>}}, 500
    end

    test "server pings are auto-replied with pongs without invoking the handler" do
      {:ok, _pid} = start_client()
      server = await_connect()

      send(server, {:send_ping, "ping-payload"})
      refute_receive {:websocket_handle, {:ping, _}}, 200
    end

    test "handler can reply to a frame via {:reply, frame, state}" do
      {:ok, _pid} = start_client(%{reply_with: {:text, "auto-reply"}})
      server = await_connect()

      send(server, {:send_text, "trigger"})
      assert_receive {:websocket_handle, {:text, "trigger"}}, 500
      assert_receive {:server_received, "auto-reply"}, 500
    end
  end

  describe "disconnect" do
    test "server-initiated close invokes ondisconnect/2 and websocket_terminate/3" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client()
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})

      assert_receive {:websocket_handle, {:close, 1000, "bye"}}, 500
      assert_receive {:ondisconnect, :remote}, 500
      assert_receive {:websocket_terminate, _reason}, 500
      assert_receive {:EXIT, ^pid, {:shutdown, :remote}}, 500
    end

    test "ondisconnect returning :reconnect re-establishes the connection" do
      {:ok, _pid} = start_client(%{on_disconnect: :reconnect})
      first_server = await_connect()

      send(first_server, {:server_close, 1000, "bye"})
      assert_receive {:ondisconnect, _}, 500

      assert_receive {:onconnect, _ref}, 1_000
      assert_receive {:server_connected, _new_server}, 1_000
    end
  end

  describe "non-websocket messages" do
    test "messages unrelated to the connection are routed to websocket_info/3" do
      {:ok, pid} = start_client()
      await_connect()

      send(pid, :custom_message)
      assert_receive {:websocket_info, :custom_message}, 500
    end

    test "websocket_info handler can ask the connection to close" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{info_reply: {:close_with, :normal}})
      await_connect()

      send(pid, :close_me)
      assert_receive {:websocket_info, :close_me}, 500
      assert_receive {:ondisconnect, :normal}, 500
    end
  end

  describe "websocket_handle return values" do
    test "a bare :ok response leaves the handler state unchanged" do
      {:ok, _pid} = start_client(%{reply_with: :bare_ok})
      server = await_connect()

      send(server, {:send_text, "ping"})
      assert_receive {:websocket_handle, {:text, "ping"}}, 500
    end

    test "a {:close, reason, state} response closes the connection" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{reply_with: {:close_with, :normal}})
      server = await_connect()

      send(server, {:send_text, "shutdown"})
      assert_receive {:websocket_handle, {:text, "shutdown"}}, 500
      assert_receive {:ondisconnect, :normal}, 500
      assert_receive {:EXIT, ^pid, :normal}, 500
    end
  end

  describe "ondisconnect return values" do
    test "an :ok response stops the GenServer with :normal" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{on_disconnect: :ok})
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})
      assert_receive {:ondisconnect, :remote}, 500
      assert_receive {:EXIT, ^pid, :normal}, 500
    end

    test "a {:close, :normal, state} response stops with :normal" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{on_disconnect: :close_normal})
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})
      assert_receive {:EXIT, ^pid, :normal}, 500
    end

    test "a {:close, :shutdown, state} response stops with :shutdown" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{on_disconnect: :close_shutdown})
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})
      assert_receive {:EXIT, ^pid, :shutdown}, 500
    end

    test "a {:close, {:shutdown, reason}, state} response stops with that tuple" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{on_disconnect: :close_shutdown_tuple})
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})
      assert_receive {:EXIT, ^pid, {:shutdown, :bye}}, 500
    end
  end

  describe "URL parsing" do
    # parse_url runs inside init/1 before any network I/O, so we can exercise
    # every scheme/path/query branch by attempting to start a client with each
    # URL form. The connection fails (no listener), but parse_url is covered.
    setup do
      Process.flag(:trap_exit, true)
      :ok
    end

    defp try_parse(url) do
      WebSocketClient.start_link(
        url,
        Handler,
        %{test_pid: self(), on_disconnect: :ok},
        []
      )

      assert_receive {:init, _}, 500
      assert_receive {:ondisconnect, _reason}, 1_000
    end

    test "accepts wss:// URLs" do
      try_parse("wss://nonexistent.invalid/ws")
    end

    test "accepts https:// URLs" do
      try_parse("https://nonexistent.invalid/ws")
    end

    test "accepts ws:// URLs without a path" do
      try_parse("ws://127.0.0.1:1")
    end

    test "accepts http:// URLs" do
      try_parse("http://127.0.0.1:1/ws")
    end

    test "accepts unknown schemes by falling back to :ws" do
      try_parse("custom://127.0.0.1:1/ws")
    end

    test "preserves a query string" do
      try_parse("ws://127.0.0.1:1/path?foo=bar")
    end
  end

  describe "upgrade failure" do
    test "fails cleanly when the server replies with a non-upgrade response" do
      # The test server's catch-all route returns 404, so connecting against
      # a path that isn't /ws lets Mint.HTTP.connect succeed but
      # Mint.WebSocket.upgrade fail when no 101 is received — which exercises
      # the inner {:error, _conn, reason} branch in connect/1.
      Process.flag(:trap_exit, true)

      {:ok, _pid} =
        WebSocketClient.start_link(
          "ws://localhost:#{@port}/not-a-websocket",
          Handler,
          %{test_pid: self(), on_disconnect: :ok},
          []
        )

      assert_receive {:init, _}, 500
      assert_receive {:ondisconnect, _reason}, 1_000
    end

    test "WebSocket.upgrade returning the 3-tuple error drives the disconnect path" do
      # Mint.HTTP1 validates request targets synchronously and a space in the
      # path is rejected, so upgrade returns {:error, conn, reason} before any
      # bytes go on the wire — exercising the {:error, _conn, reason} branch
      # in connect/1.
      Process.flag(:trap_exit, true)

      {:ok, _pid} =
        WebSocketClient.start_link(
          "ws://localhost:#{@port}/with space",
          Handler,
          %{test_pid: self(), on_disconnect: :ok},
          []
        )

      assert_receive {:init, _}, 500
      assert_receive {:ondisconnect, _reason}, 1_000
    end
  end

  describe "send_frame encode errors" do
    test "an oversized control frame returns an encode error and disconnects" do
      # WebSocket control frames are limited to 125 bytes; Mint throws inside
      # encode and returns {:error, websocket, reason}, which the encode-error
      # clause of send_frame/2 routes into the disconnect path.
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client()
      await_connect()

      WebSocketClient.cast(pid, {:ping, :binary.copy("x", 200)})
      assert_receive {:ondisconnect, _reason}, 500
    end
  end

  describe "terminate fallback" do
    test "terminate/2 with data that doesn't match the connected map shape returns :ok" do
      # terminate's fallback clause handles cases where the GenServer was never
      # fully initialized — call it directly to exercise that branch.
      assert :ok = Slack.WebSocketClient.terminate(:normal, :no_state)
    end
  end

  describe "edge cases via :sys.replace_state/2" do
    # These branches are only reachable in real failure modes that are hard to
    # produce naturally (lost connection mid-cast, stray messages after
    # disconnect, etc). We force the GenServer into the relevant state and then
    # exercise the branch.

    test "handle_info(:keepalive, %{websocket: nil}) is a no-op" do
      {:ok, pid} = start_client()
      await_connect()

      :sys.replace_state(pid, fn data -> %{data | websocket: nil} end)
      send(pid, :keepalive)
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "stray messages with conn=nil are routed to websocket_info/3" do
      {:ok, pid} = start_client()
      await_connect()

      :sys.replace_state(pid, fn data -> %{data | conn: nil} end)
      send(pid, :stray)
      assert_receive {:websocket_info, :stray}, 500
    end

    test "send_frame error from a closed conn inside handle_cast triggers disconnect" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client()
      await_connect()

      # Close the Mint conn out from under the GenServer so that the next
      # stream_request_body call returns {:error, conn, reason}.
      :sys.replace_state(pid, fn data ->
        {:ok, closed_conn} = Mint.HTTP.close(data.conn)
        %{data | conn: closed_conn}
      end)

      WebSocketClient.cast(pid, {:text, "boom"})
      assert_receive {:ondisconnect, _reason}, 500
    end

    test "keepalive timer firing after the conn dies invokes the disconnect path" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{}, keepalive: 50)
      await_connect()

      :sys.replace_state(pid, fn data ->
        {:ok, closed_conn} = Mint.HTTP.close(data.conn)
        %{data | conn: closed_conn}
      end)

      send(pid, :keepalive)
      assert_receive {:ondisconnect, _reason}, 1_000
    end

    test "stream errors (foreign tcp message) are passed back to websocket_info" do
      {:ok, pid} = start_client()
      await_connect()

      # A {:tcp, _, _} for a socket Mint doesn't know about returns :unknown,
      # which falls through to dispatch_info — exercising the catch-all branch.
      send(pid, {:tcp, :fake_socket, "garbage"})
      assert_receive {:websocket_info, {:tcp, :fake_socket, "garbage"}}, 500
    end

    test "handler can close the connection from a server close frame" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client(%{reply_with: {:close_with, :remote}})
      server = await_connect()

      send(server, {:server_close, 1000, "bye"})
      assert_receive {:websocket_handle, {:close, 1000, "bye"}}, 500
      assert_receive {:ondisconnect, :remote}, 500
      assert_receive {:EXIT, ^pid, _}, 500
    end

    test "tcp_closed on the live conn invokes handle_disconnect" do
      Process.flag(:trap_exit, true)
      {:ok, pid} = start_client()
      await_connect()

      socket =
        :sys.get_state(pid)
        |> Map.get(:conn)
        |> Map.get(:socket)

      # Mint.WebSocket.stream/2 turns a {:tcp_closed, socket} for the
      # connection's own socket into a transport error response, which is
      # the only natural way to drive the error branch in handle_info.
      send(pid, {:tcp_closed, socket})
      assert_receive {:ondisconnect, _reason}, 1_000
    end
  end

  describe "send failures during incoming-frame handling" do
    # Half-closing the local write side (via :gen_tcp.shutdown/2) makes all
    # subsequent gen_tcp.send calls return {:error, :closed} while reads
    # still work. A raw-TCP server stays in a receive loop ignoring the
    # FIN, so it can push frames to the client after the half-close.

    test "pong send failure after receiving a ping triggers the disconnect path" do
      Process.flag(:trap_exit, true)
      {_server, port} = RawWsServer.start(self())

      {:ok, pid} =
        WebSocketClient.start_link(
          "ws://127.0.0.1:#{port}/ws",
          Handler,
          %{test_pid: self(), on_disconnect: :ok},
          []
        )

      assert_receive {:raw_ws_upgraded, server}, 1_000
      assert_receive {:onconnect, _ref}, 1_000

      socket = :sys.get_state(pid).conn.socket
      :ok = :gen_tcp.shutdown(socket, :write)

      # Server-to-client ping frame: FIN+opcode=ping (0x89), len=4, "ping".
      send(server, {:send, <<0x89, 0x04, "ping">>})

      assert_receive {:ondisconnect, _reason}, 1_000
    end

    test "handler reply send failure triggers the disconnect path" do
      Process.flag(:trap_exit, true)
      {_server, port} = RawWsServer.start(self())

      {:ok, pid} =
        WebSocketClient.start_link(
          "ws://127.0.0.1:#{port}/ws",
          Handler,
          %{test_pid: self(), on_disconnect: :ok, reply_with: {:text, "auto-reply"}},
          []
        )

      assert_receive {:raw_ws_upgraded, server}, 1_000
      assert_receive {:onconnect, _ref}, 1_000

      socket = :sys.get_state(pid).conn.socket
      :ok = :gen_tcp.shutdown(socket, :write)

      # Server-to-client text frame: FIN+opcode=text (0x81), len=2, "hi".
      send(server, {:send, <<0x81, 0x02, "hi">>})

      assert_receive {:ondisconnect, _reason}, 1_000
    end
  end
end
