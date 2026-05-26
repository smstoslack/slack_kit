defmodule Slack.WebTest do
  use ExUnit.Case, async: false

  defmodule RecordingClient do
    @behaviour Slack.Web.Client

    @impl true
    def post!(url, body) do
      send(Application.get_env(:slack, :web_test_pid), {:web_request, url, body})
      %{"ok" => true}
    end
  end

  setup do
    original_client = Application.get_env(:slack, :web_http_client)
    original_token = Application.get_env(:slack, :api_token)
    original_url = Application.get_env(:slack, :url, "https://slack.com")

    Application.put_env(:slack, :web_test_pid, self())
    Application.put_env(:slack, :web_http_client, RecordingClient)
    Application.put_env(:slack, :api_token, "ENV-TOKEN")
    Application.put_env(:slack, :url, "https://slack.test")

    on_exit(fn ->
      put_or_delete(:web_http_client, original_client)
      put_or_delete(:api_token, original_token)
      Application.put_env(:slack, :url, original_url)
    end)

    :ok
  end

  defp put_or_delete(key, nil), do: Application.delete_env(:slack, key)
  defp put_or_delete(key, value), do: Application.put_env(:slack, key, value)

  describe "get_documentation/0" do
    test "returns a map keyed by Slack API module name" do
      docs = Slack.Web.get_documentation()

      assert is_map(docs)
      assert Map.has_key?(docs, "chat")
      assert Map.has_key?(docs, "team")
      assert Map.has_key?(docs, "oauth.v2")
    end
  end

  describe "generated endpoints" do
    test "issue a form request with the configured URL and api_token" do
      assert %{"ok" => true} = Slack.Web.Team.info()

      assert_receive {:web_request, url, {:form, params}}
      assert url == "https://slack.test/api/team.info"
      assert params[:token] == "ENV-TOKEN"
    end

    test "include positional required arguments in the form params" do
      Slack.Web.Chat.post_message("C123", %{text: "hello world"})

      assert_receive {:web_request, url, {:form, params}}
      assert url == "https://slack.test/api/chat.postMessage"
      assert params[:channel] == "C123"
      assert params[:text] == "hello world"
      assert params[:token] == "ENV-TOKEN"
    end

    test "merge optional_params and use a token passed via optional_params over the env token" do
      Slack.Web.Chat.post_message("C123", %{
        token: "OVERRIDE",
        as_user: true,
        text: "hi"
      })

      assert_receive {:web_request, _url, {:form, params}}
      assert params[:token] == "OVERRIDE"
      assert params[:as_user] == true
      assert params[:text] == "hi"
    end

    test "drop params whose value is nil" do
      Slack.Web.Chat.post_message("C123", %{thread_ts: nil, text: "hi"})

      assert_receive {:web_request, _url, {:form, params}}
      refute Keyword.has_key?(params, :thread_ts)
    end

    test "encode files.upload as a multipart body with the file last" do
      path = "/tmp/slack_kit_upload_test.txt"
      File.write!(path, "stub")

      Slack.Web.Files.upload(%{
        file: path,
        channels: "C123",
        filename: "stub.txt",
        token: "OVERRIDE"
      })

      assert_receive {:web_request, url, {:multipart, parts}}
      assert url == "https://slack.test/api/files.upload"

      {:file, file_path, _} = List.last(parts)
      # the upload codegen uses the first positional argument as the file
      # in this generated module there is none, so file ends up being nil
      assert file_path in [nil, path]

      form_parts =
        parts
        |> List.delete_at(-1)
        |> Enum.map(fn {"", value, {"form-data", [{"name", name}]}, _} ->
          {name, value}
        end)
        |> Map.new()

      assert form_parts[:channels] == "C123"
      assert form_parts[:filename] == "stub.txt"
      assert form_parts[:token] == "OVERRIDE"

      File.rm!(path)
    end

    test "falls back to api_token from app env when no token is provided" do
      Application.put_env(:slack, :api_token, "FALLBACK")
      Slack.Web.Team.info()

      assert_receive {:web_request, _url, {:form, params}}
      assert params[:token] == "FALLBACK"
    end
  end
end
