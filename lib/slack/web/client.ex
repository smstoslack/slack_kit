defmodule Slack.Web.Client do
  @moduledoc """
  Behaviour for a pluggable Slack Web API HTTP client.

  Every function generated under `Slack.Web.*` calls `post!/2` on the module
  configured as `:web_http_client` (default: `Slack.Web.DefaultClient`).
  Implementing this behaviour lets you inject auth headers, add retries,
  decorate responses, route requests through a proxy, or instrument calls
  for telemetry without touching the generated code.

  The return value of `post!/2` is handed back to the caller of the
  `Slack.Web.*` function unchanged — there is no required shape, so a custom
  client is free to wrap the response in `{:ok, _}` / `{:error, _}` tuples
  or in a struct of its choosing.

  ## Example

      defmodule MyApp.SlackClient do
        @behaviour Slack.Web.Client

        @impl true
        def post!(url, {:form, params}) do
          url
          |> Req.post!(form: params, retry: :transient)
          |> Map.fetch!(:body)
          |> JSON.decode!()
          |> wrap()
        end

        def post!(url, {:multipart, _parts} = body) do
          # Fall back to the default client for multipart uploads.
          Slack.Web.DefaultClient.post!(url, body)
        end

        defp wrap(%{"ok" => true} = body), do: {:ok, body}
        defp wrap(%{"error" => reason} = body), do: {:error, reason, body}
      end

      # config/runtime.exs
      config :slack, :web_http_client, MyApp.SlackClient

  See `Slack.Web.DefaultClient` for the stock implementation built on `Req`.
  """

  @type url :: String.t()
  @type form_body :: {:form, Keyword.t()}
  @type multipart_form_body :: {:multipart, nonempty_list(tuple())}
  @type body :: form_body() | multipart_form_body()

  @doc """
  Performs a POST against `url` with `body`.

  `body` is either `{:form, params}` for most endpoints or
  `{:multipart, parts}` for file uploads. The return value is passed
  through to the caller of the generated `Slack.Web.*` function verbatim
  and may be any term.
  """
  @callback post!(url :: url, body :: body) :: term()
end
