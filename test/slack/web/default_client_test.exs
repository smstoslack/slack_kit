defmodule Slack.Web.DefaultClientTest do
  use ExUnit.Case, async: false

  alias Slack.Web.DefaultClient

  setup do
    original = Application.get_env(:slack, :web_http_client_opts, [])
    on_exit(fn -> Application.put_env(:slack, :web_http_client_opts, original) end)
    :ok
  end

  defp put_plug(plug) do
    Application.put_env(:slack, :web_http_client_opts, plug: plug)
  end

  test "post!/2 with a :form body decodes a JSON body" do
    put_plug(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:got_body, body})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"ok":true,"echo":"hi"}))
    end)

    assert %{"ok" => true, "echo" => "hi"} =
             DefaultClient.post!("http://x.test/api/foo", {:form, [text: "hi"]})
  end

  test "post!/2 returns the body untouched when it is not a binary" do
    put_plug(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"ok":true}))
    end)

    body = DefaultClient.post!("http://x.test/api/foo", {:form, [text: "hi"]})
    assert body == %{"ok" => true}
  end

  test "post!/2 JSON-decodes the body when Req returns it as a binary" do
    put_plug(fn conn ->
      # No content-type/decode-body header so Req keeps the body as a binary.
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, ~s({"ok":true,"raw":"yes"}))
    end)

    assert %{"ok" => true, "raw" => "yes"} =
             DefaultClient.post!("http://x.test/api/foo", {:form, [text: "hi"]})
  end

  test "post!/2 with a :multipart body builds file streams and form fields" do
    path = "/tmp/slack_kit_default_client.txt"
    File.write!(path, "contents")

    put_plug(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"ok":true}))
    end)

    parts = [
      {"", "C123", {"form-data", [{"name", :channels}]}, []},
      {"", "OVERRIDE", {"form-data", [{"name", "token"}]}, []},
      {:file, path, []}
    ]

    assert %{"ok" => true} = DefaultClient.post!("http://x.test/api/files.upload", {:multipart, parts})

    File.rm!(path)
  end
end
