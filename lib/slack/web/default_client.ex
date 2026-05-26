defmodule Slack.Web.DefaultClient do
  @moduledoc """
  Default http client used for all requests to Slack Web API.

  All Slack RPC method calls are delivered via post and are dangerous by
  default, raising on any HTTP response that doesn't contain a body field.

  Parsed body data is returned unwrapped to the caller.

  Additional error handling or response wrapping can be controlled as needed
  by configuring a custom client module.

  ## Examples

      config :slack, :web_http_client, YourApp.CustomClient

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

  defp decode_body(body) when is_binary(body), do: Jason.decode!(body)
  defp decode_body(body), do: body

  defp opts do
    Application.get_env(:slack, :web_http_client_opts, [])
  end
end
