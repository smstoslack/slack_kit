defmodule Slack.FakeSlack do
  @moduledoc false

  def start_link do
    Application.put_env(:slack, :url, "http://localhost:51345")

    Plug.Cowboy.http(
      Slack.FakeSlack.Router,
      [],
      port: 51_345,
      dispatch: dispatch()
    )
  end

  def stop do
    Plug.Cowboy.shutdown(Slack.FakeSlack.Router.HTTP)
  end

  defp dispatch do
    [
      {
        :_,
        [
          {"/ws", Slack.FakeSlack.Websocket, []},
          {:_, Plug.Cowboy.Handler, {Slack.FakeSlack.Router, []}}
        ]
      }
    ]
  end
end
