defmodule Slack.SendsTest do
  use ExUnit.Case
  alias Slack.Sends

  defmodule FakeWebsocketClient do
    def send({:text, json}, socket) do
      {json, socket}
    end

    def cast(pid, {:text, json}) do
      {pid, json}
    end
  end

  test "send_raw sends slack formatted to client" do
    result = Sends.send_raw(~s/{"text": "foo"}/, %{process: 123, client: FakeWebsocketClient})
    assert result == {123, ~s/{"text": "foo"}/}
  end

  test "send_message sends message formatted to client" do
    result = Sends.send_message("hello", "channel", %{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"message","text":"hello","channel":"channel"}/}
  end

  test "send_message understands #channel names" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      channels: %{"C456" => %{name: "channel", id: "C456"}}
    }

    result = Sends.send_message("hello", "#channel", slack)
    assert result == {nil, ~s/{"type":"message","text":"hello","channel":"C456"}/}
  end

  test "send_message understands @user names" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      users: %{"U123" => %{name: "user", id: "U123"}},
      ims: %{"D789" => %{user: "U123", id: "D789"}}
    }

    result = Sends.send_message("hello", "@user", slack)
    assert result == {nil, ~s/{"type":"message","text":"hello","channel":"D789"}/}
  end

  test "send_message understands user ids (Uxxx)" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      users: %{"U123" => %{name: "user", id: "U123"}},
      ims: %{"D789" => %{user: "U123", id: "D789"}}
    }

    result = Sends.send_message("hello", "U123", slack)
    assert result == {nil, ~s/{"type":"message","text":"hello","channel":"D789"}/}
  end

  test "send_message understands user ids (Wxxx)" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      users: %{"W123" => %{name: "user", id: "W123"}},
      ims: %{"D789" => %{user: "W123", id: "D789"}}
    }

    result = Sends.send_message("hello", "W123", slack)
    assert result == {nil, ~s/{"type":"message","text":"hello","channel":"D789"}/}
  end

  test "send_message with a thread attribute includes thread_ts in message to client" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      users: %{"U123" => %{name: "user", id: "U123"}},
      ims: %{"D789" => %{user: "U123", id: "D789"}}
    }

    result = Sends.send_message("hello", "D789", slack, "1555508888.000100")

    assert result ==
             {nil,
              ~s/{"type":"message","text":"hello","channel":"D789","thread_ts":"1555508888.000100"}/}
  end

  test "indicate_typing sends typing notification to client" do
    result = Sends.indicate_typing("channel", %{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"typing","channel":"channel"}/}
  end

  test "send_ping sends ping to client" do
    result = Sends.send_ping(%{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"ping"}/}
  end

  test "send_ping with data sends ping + data to client" do
    result = Sends.send_ping(%{foo: :bar}, %{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"ping","foo":"bar"}/}
  end

  test "subscribe_presence sends presence subscription message to client" do
    result = Sends.subscribe_presence(["a_user_id"], %{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"presence_sub","ids":["a_user_id"]}/}
  end

  test "subscribe_presence without ids sends presence subscription message to client" do
    result = Sends.subscribe_presence(%{process: nil, client: FakeWebsocketClient})
    assert result == {nil, ~s/{"type":"presence_sub","ids":[]}/}
  end

  test "send_message/3 raises ArgumentError when #channel is not found" do
    slack = %{process: nil, client: FakeWebsocketClient, channels: %{}, groups: %{}}

    assert_raise ArgumentError, "channel #missing not found", fn ->
      Sends.send_message("hi", "#missing", slack)
    end
  end

  test "send_message/4 with thread routes #channel through lookup" do
    slack = %{
      process: nil,
      client: FakeWebsocketClient,
      channels: %{"C456" => %{name: "channel", id: "C456"}}
    }

    result = Sends.send_message("hi", "#channel", slack, "1.2")

    assert result ==
             {nil, ~s/{"type":"message","text":"hi","channel":"C456","thread_ts":"1.2"}/}
  end

  test "send_message/4 raises ArgumentError when #channel is not found" do
    slack = %{process: nil, client: FakeWebsocketClient, channels: %{}, groups: %{}}

    assert_raise ArgumentError, "channel #missing not found", fn ->
      Sends.send_message("hi", "#missing", slack, "1.2")
    end
  end

  describe "send_message/3 opens IM channel when none is cached" do
    setup do
      original_url = Application.get_env(:slack, :url, "https://slack.com")
      original_opts = Application.get_env(:slack, :web_http_client_opts, [])

      Application.put_env(:slack, :url, "http://im.open.fake")

      on_exit(fn ->
        Application.put_env(:slack, :url, original_url)
        Application.put_env(:slack, :web_http_client_opts, original_opts)
      end)

      :ok
    end

    test "sends to the newly opened DM channel" do
      Application.put_env(:slack, :web_http_client_opts,
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"channel":{"id":"D999"}}))
        end
      )

      slack = %{
        process: nil,
        client: FakeWebsocketClient,
        token: "abc",
        users: %{"U123" => %{name: "user", id: "U123"}},
        ims: %{}
      }

      result = Sends.send_message("hello", "U123", slack)
      assert result == {nil, ~s/{"type":"message","text":"hello","channel":"D999"}/}
    end

    test "returns error map when Slack returns an error" do
      Application.put_env(:slack, :web_http_client_opts,
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 200, ~s({"ok":false,"error":"user_not_found"}))
        end
      )

      slack = %{
        process: nil,
        client: FakeWebsocketClient,
        token: "abc",
        users: %{"U123" => %{name: "user", id: "U123"}},
        ims: %{}
      }

      assert %{error: "user_not_found"} = Sends.send_message("hello", "U123", slack)
    end

    test "returns the transport reason when Req fails" do
      Application.put_env(:slack, :web_http_client_opts,
        plug: fn conn -> Req.Test.transport_error(conn, :nxdomain) end,
        retry: false
      )

      slack = %{
        process: nil,
        client: FakeWebsocketClient,
        token: "abc",
        users: %{"U123" => %{name: "user", id: "U123"}},
        ims: %{}
      }

      assert %Req.TransportError{reason: :nxdomain} =
               Sends.send_message("hello", "U123", slack)
    end
  end
end
