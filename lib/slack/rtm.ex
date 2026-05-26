defmodule Slack.JsonDecodeError do
  @moduledoc false

  defexception [:reason, :string]

  def message(%Slack.JsonDecodeError{reason: reason, string: string}) do
    "Could not decode JSON for reason: #{inspect(reason)}, string given:\n#{string}"
  end
end

defmodule Slack.Rtm do
  @moduledoc false

  def start(token) do
    with url <- slack_url(token),
         options <- Application.get_env(:slack, :web_http_client_opts, []) do
      url
      |> Req.get(Keyword.put(options, :decode_body, false))
      |> handle_response()
    end
  end

  defp handle_response({:ok, %Req.Response{body: body}}) do
    case JSON.decode(body) do
      {:ok, decoded} ->
        case Slack.JSON.atomize_keys(decoded) do
          %{ok: true} = json ->
            {:ok, json}

          %{error: reason} ->
            {:error, "Slack API returned an error `#{reason}.\n Response: #{body}"}

          _ ->
            {:error, "Invalid RTM response"}
        end

      {:error, reason} ->
        {:error, %Slack.JsonDecodeError{reason: reason, string: body}}
    end
  end

  defp handle_response(error), do: error

  defp slack_url(token) do
    Application.get_env(:slack, :url, "https://slack.com") <>
      "/api/rtm.start?token=#{token}&batch_presence_aware=true&presence_sub=true"
  end
end
