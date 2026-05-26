defmodule Slack.FakeSlack.Websocket do
  @moduledoc false

  @behaviour :cowboy_websocket

  @activity_timeout 5000

  def init(req, _opts) do
    {:cowboy_websocket, req, %{}, %{idle_timeout: @activity_timeout}}
  end

  def websocket_init(state) do
    pid = Application.get_env(:slack, :test_pid)
    send(pid, {:websocket_connected, self()})

    {:ok, state}
  end

  def websocket_handle({:text, "ping"}, state) do
    {:reply, {:text, "pong"}, state}
  end

  def websocket_handle({:text, message}, state) do
    pid = Application.get_env(:slack, :test_pid)
    send(pid, {:bot_message, JSON.decode!(message)})

    {:ok, state}
  end

  def websocket_info(message, state) do
    {:reply, {:text, message}, state}
  end

  def terminate(_reason, _req, _state) do
    :ok
  end
end
