defmodule Slack.BotTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  defmodule Bot do
    use Slack

    def handle_connect(slack, state) do
      send(state.test_pid, {:bot_connect, slack})
      {:ok, state}
    end

    def handle_event(event, _slack, state) do
      send(state.test_pid, {:bot_event, event})
      {:ok, state}
    end

    def handle_info(message, _slack, state) do
      send(state.test_pid, {:bot_info, message})
      {:ok, state}
    end

    def handle_close(reason, _slack, state) do
      send(state.test_pid, {:bot_close, reason})
      :close
    end
  end

  defmodule CrashingBot do
    use Slack

    def handle_event(_, _, _state), do: raise("boom in handle_event")
    def handle_info(_, _, _state), do: raise("boom in handle_info")
    def handle_close(_reason, _, _state), do: raise("boom in handle_close")
  end

  @rtm %{
    url: "http://example.com",
    self: %{name: "fake"},
    team: %{name: "Foo"}
  }

  defmodule FakeWebsocketClient do
    def start_link(_url, _module, _state, _opts) do
      {:ok, self()}
    end

    def cast(_pid, _frame), do: :ok
  end

  defp init_state(extra \\ %{}) do
    base = %{
      bot_handler: Bot,
      rtm: @rtm,
      client: FakeWebsocketClient,
      token: "ABC",
      initial_state: %{test_pid: self()}
    }

    {:reconnect, state} = Slack.Bot.init(Map.merge(base, extra))
    state
  end

  test "init formats rtm results properly" do
    {:reconnect, %{slack: slack, bot_handler: bot_handler}} =
      Slack.Bot.init(%{
        bot_handler: Bot,
        rtm: @rtm,
        client: FakeWebsocketClient,
        token: "ABC",
        initial_state: %{test_pid: self()}
      })

    assert bot_handler == Bot
    assert slack.me.name == "fake"
    assert slack.team.name == "Foo"
    assert slack.token == "ABC"
    assert slack.client == FakeWebsocketClient
  end

  test "onconnect/2 invokes handle_connect with current slack and state" do
    state = init_state()
    {:ok, new_state} = Slack.Bot.onconnect(:websocket_request, state)
    assert_receive {:bot_connect, slack}
    assert slack.me.name == "fake"
    assert new_state.process_state == state.process_state
  end

  test "ondisconnect/2 with :keepalive_timeout reconnects" do
    state = init_state()
    assert {:reconnect, ^state} = Slack.Bot.ondisconnect({:error, :keepalive_timeout}, state)
  end

  test "ondisconnect/2 delegates to handle_close and returns :close" do
    state = init_state()
    assert {:close, :remote, ^state} = Slack.Bot.ondisconnect(:remote, state)
    assert_receive {:bot_close, :remote}
  end

  test "ondisconnect/2 re-raises and logs when handle_close crashes" do
    state = init_state(%{bot_handler: CrashingBot})

    captured =
      capture_log(fn ->
        assert_raise RuntimeError, "boom in handle_close", fn ->
          Slack.Bot.ondisconnect(:remote, state)
        end
      end)

    assert captured =~ "boom in handle_close"
  end

  test "websocket_info/3 invokes handle_info" do
    state = init_state()
    {:ok, _new_state} = Slack.Bot.websocket_info(:custom_message, :conn, state)
    assert_receive {:bot_info, :custom_message}
  end

  test "websocket_info/3 re-raises and logs when handle_info crashes" do
    state = init_state(%{bot_handler: CrashingBot})

    captured =
      capture_log(fn ->
        assert_raise RuntimeError, "boom in handle_info", fn ->
          Slack.Bot.websocket_info(:msg, :conn, state)
        end
      end)

    assert captured =~ "boom in handle_info"
  end

  test "websocket_terminate/3 returns :ok" do
    assert :ok = Slack.Bot.websocket_terminate(:normal, :conn, %{})
  end

  test "websocket_handle/3 with non-text frame returns state unchanged" do
    state = init_state()
    assert {:ok, ^state} = Slack.Bot.websocket_handle({:binary, <<1, 2>>}, :conn, state)
  end

  test "websocket_handle/3 with a typed message updates slack state and dispatches" do
    state = init_state()
    json = JSON.encode!(%{type: "team_rename", name: "Updated"})

    {:ok, new_state} = Slack.Bot.websocket_handle({:text, json}, :conn, state)

    assert new_state.slack.team.name == "Updated"
    assert_receive {:bot_event, %{type: "team_rename", name: "Updated"}}
  end

  test "websocket_handle/3 with a typeless payload skips dispatch" do
    state = init_state()
    json = JSON.encode!(%{hello: "world"})

    {:ok, new_state} = Slack.Bot.websocket_handle({:text, json}, :conn, state)

    assert new_state.slack == state.slack
    refute_received {:bot_event, _}
  end

  test "websocket_handle/3 trims trailing null bytes before decoding" do
    state = init_state()
    json = JSON.encode!(%{type: "team_rename", name: "Trimmed"}) <> <<0, "garbage">>

    {:ok, new_state} = Slack.Bot.websocket_handle({:text, json}, :conn, state)
    assert new_state.slack.team.name == "Trimmed"
  end

  test "websocket_handle/3 re-raises and logs when handle_event crashes" do
    state = init_state(%{bot_handler: CrashingBot})
    json = JSON.encode!(%{type: "team_rename", name: "Oops"})

    captured =
      capture_log(fn ->
        assert_raise RuntimeError, "boom in handle_event", fn ->
          Slack.Bot.websocket_handle({:text, json}, :conn, state)
        end
      end)

    assert captured =~ "boom in handle_event"
  end

  describe "start_link/4" do
    setup do
      original = Application.get_env(:slack, :rtm_module, Slack.Rtm)

      on_exit(fn ->
        Application.put_env(:slack, :rtm_module, original)
      end)

      :ok
    end

    defmodule Stubs.Slack.Rtm do
      def start(_token), do: {:ok, %{url: "http://www.example.com"}}
    end

    defmodule Stubs.RtmTimeout do
      def start(_token), do: {:error, %Req.TransportError{reason: :timeout}}
    end

    defmodule Stubs.RtmNxdomain do
      def start(_token), do: {:error, %Req.TransportError{reason: :nxdomain}}
    end

    defmodule Stubs.RtmTooManyRequests do
      def start(_token),
        do:
          {:error,
           %Slack.JsonDecodeError{
             reason: :unexpected,
             string: "You are sending too many requests. Please relax."
           }}
    end

    defmodule Stubs.RtmGenericError do
      def start(_token), do: {:error, :something_else}
    end

    test "starts and registers a name when given one" do
      Application.put_env(:slack, :rtm_module, Stubs.Slack.Rtm)

      assert {:ok, pid} =
               Slack.Bot.start_link(Bot, %{test_pid: self()}, "token", %{
                 client: FakeWebsocketClient,
                 name: :named_slack_bot
               })

      assert Process.whereis(:named_slack_bot) == pid
    end

    test "returns timeout error" do
      Application.put_env(:slack, :rtm_module, Stubs.RtmTimeout)

      assert {:error, "Timed out while connecting to the Slack RTM API"} =
               Slack.Bot.start_link(Bot, %{}, "token", %{client: FakeWebsocketClient})
    end

    test "returns nxdomain error" do
      Application.put_env(:slack, :rtm_module, Stubs.RtmNxdomain)

      assert {:error, "Could not connect to the Slack RTM API"} =
               Slack.Bot.start_link(Bot, %{}, "token", %{client: FakeWebsocketClient})
    end

    test "returns rate-limit error" do
      Application.put_env(:slack, :rtm_module, Stubs.RtmTooManyRequests)

      assert {:error, "Sent too many connection requests at once to the Slack RTM API."} =
               Slack.Bot.start_link(Bot, %{}, "token", %{client: FakeWebsocketClient})
    end

    test "passes through any other error" do
      Application.put_env(:slack, :rtm_module, Stubs.RtmGenericError)

      assert {:error, :something_else} =
               Slack.Bot.start_link(Bot, %{}, "token", %{client: FakeWebsocketClient})
    end
  end
end
