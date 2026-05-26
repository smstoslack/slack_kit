defmodule Slack.RtmTest do
  use ExUnit.Case, async: false

  alias Slack.Rtm

  setup do
    original_opts = Application.get_env(:slack, :web_http_client_opts, [])

    on_exit(fn ->
      Application.put_env(:slack, :web_http_client_opts, original_opts)
    end)

    :ok
  end

  defp put_plug(plug) do
    Application.put_env(:slack, :web_http_client_opts, plug: plug)
  end

  test "returns {:ok, json} on a successful response" do
    put_plug(fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"url":"ws://example.com"}))
    end)

    assert {:ok, payload} = Rtm.start("token")
    assert payload.ok == true
    assert payload.url == "ws" <> "://example.com"
  end

  test "returns {:error, message} when Slack returns an error payload" do
    put_plug(fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s/{"ok":false,"error":"invalid_auth"}/)
    end)

    assert {:error, msg} = Rtm.start("token")
    assert msg =~ "Slack API returned an error"
    assert msg =~ "invalid_auth"
  end

  test "returns an Invalid RTM response error when the payload has no ok/error keys" do
    put_plug(fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s/{"unexpected":true}/)
    end)

    assert {:error, "Invalid RTM response"} = Rtm.start("token")
  end

  test "wraps JSON decode failures in Slack.JsonDecodeError" do
    put_plug(fn conn ->
      Plug.Conn.send_resp(conn, 200, "not-json")
    end)

    assert {:error, %Slack.JsonDecodeError{string: "not-json"} = err} = Rtm.start("token")

    message = Exception.message(err)
    assert message =~ "Could not decode JSON for reason"
    assert message =~ "not-json"
  end

  test "passes through Req errors unchanged" do
    Application.put_env(:slack, :web_http_client_opts,
      plug: fn conn -> Req.Test.transport_error(conn, :nxdomain) end,
      retry: false
    )

    assert {:error, %Req.TransportError{reason: :nxdomain}} = Rtm.start("token")
  end
end
