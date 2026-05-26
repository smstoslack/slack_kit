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
        :ok -> {:ok, state}
      end
    end

    def websocket_handle(frame, _ref, state) do
      send(state.test_pid, {:websocket_handle, frame})

      case Map.get(state, :reply_with) do
        nil -> {:ok, state}
        frame -> {:reply, frame, %{state | reply_with: nil}}
      end
    end

    def websocket_info(message, _ref, state) do
      send(state.test_pid, {:websocket_info, message})
      {:ok, state}
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
  end
end
