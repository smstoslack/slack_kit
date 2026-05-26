defmodule Slack.Web.DefaultClient do
  @moduledoc """
  Default `Slack.Web.Client` implementation, built on `Req`.

  Every call generated under `Slack.Web.*` is delivered as an HTTP POST. Form
  bodies are sent as `application/x-www-form-urlencoded`; uploads are sent as
  `multipart/form-data` with the file streamed from disk.

  Responses are JSON-decoded and returned **unwrapped** — i.e. the caller
  receives the body map directly, so successful calls and Slack-level errors
  (`%{"ok" => false, "error" => …}`) are surfaced identically. Transport
  failures raise via `Req.post!/2`.

  Request options can be tuned globally via the `:web_http_client_opts` config
  key:

      config :slack, :web_http_client_opts,
        connect_options: [timeout: 10_000],
        receive_timeout: 10_000

  For richer behaviour — retries, response wrapping, telemetry, custom error
  handling — swap in a module implementing `Slack.Web.Client`:

      config :slack, :web_http_client, MyApp.SlackClient
  """

  @behaviour Slack.Web.Client

  @impl true
  def post!(url, {:form, params}) do
    url
    |> Req.post!(Keyword.merge(opts(), form: params))
    |> Map.fetch!(:body)
    |> decode_body()
  end

  def post!(url, {:multipart, parts}) do
    url
    |> Req.post!(Keyword.merge(opts(), form_multipart: build_multipart(parts)))
    |> Map.fetch!(:body)
    |> decode_body()
  end

  defp build_multipart(parts) do
    Enum.map(parts, fn
      {:file, path, _} ->
        {:file, {File.stream!(path), filename: Path.basename(path)}}

      {"", value, {"form-data", [{"name", name}]}, _} ->
        {to_field_name(name), value}
    end)
  end

  defp to_field_name(name) when is_atom(name), do: name
  defp to_field_name(name) when is_binary(name), do: String.to_atom(name)

  defp decode_body(body) when is_binary(body), do: JSON.decode!(body)
  defp decode_body(body), do: body

  defp opts do
    Application.get_env(:slack, :web_http_client_opts, [])
  end
end
