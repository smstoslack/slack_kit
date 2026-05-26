defmodule Slack.Web do
  @moduledoc false

  def get_documentation do
    File.ls!("#{__DIR__}/docs")
    |> format_documentation()
  end

  defp format_documentation(files) do
    Enum.reduce(files, %{}, fn file, module_names ->
      json =
        File.read!("#{__DIR__}/docs/#{file}")
        |> JSON.decode!()

      doc = Slack.Web.Documentation.new(json, file)

      Map.update(module_names, doc.module, [doc], &(&1 ++ [doc]))
    end)
  end
end

defmodule Slack.Web.Errors do
  @common_errors_path Path.join(__DIR__, "common_errors.json")
  @external_resource @common_errors_path

  @common_errors @common_errors_path |> File.read!() |> JSON.decode!()

  @error_list @common_errors
              |> Enum.sort()
              |> Enum.map_join("\n", fn {name, desc} -> "* `#{name}` - #{desc}" end)

  @moduledoc """
  Errors returned by every Slack Web API method.

  Slack documents the same set of errors on nearly every method page —
  authentication failures, rate limiting, deprecated endpoints, transport
  problems, and so on. To keep per-method docs focused, those shared errors
  are listed here once and stripped from each method's own error list.
  Method-specific errors (e.g. `channel_not_found`, `is_archived`) remain
  on the method itself.

  ## Errors

  #{@error_list}
  """

  @doc """
  Returns the map of common error codes to their descriptions.
  """
  @spec common() :: %{String.t() => String.t()}
  def common, do: @common_errors

  @doc """
  Returns the set of error codes that are common to all Web API methods.
  """
  @spec names() :: MapSet.t(String.t())
  def names, do: MapSet.new(Map.keys(@common_errors))
end

alias Slack.Web.Documentation

Enum.each(Slack.Web.get_documentation(), fn {module_name, functions} ->
  module =
    module_name
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> then(&Module.concat([Slack.Web | &1]))

  has_upload? = Enum.any?(functions, &(&1.function == :upload))

  defmodule module do
    Enum.each(functions, fn doc ->
      function_name = doc.function

      arguments = Documentation.arguments(doc)
      argument_value_keyword_list = Documentation.arguments_with_values(doc)

      @doc """
      #{Documentation.to_doc_string(doc)}
      """
      def unquote(function_name)(unquote_splicing(arguments), optional_params \\ %{}) do
        required_params = unquote(argument_value_keyword_list)

        url = Application.get_env(:slack, :url, "https://slack.com")

        params =
          optional_params
          |> Map.to_list()
          |> Keyword.merge(required_params)
          |> Keyword.put_new(:token, get_token(optional_params))
          |> Enum.reject(fn {_, v} -> v == nil end)

        perform!(
          "#{url}/api/#{unquote(doc.endpoint)}",
          params(unquote(function_name), params, unquote(arguments))
        )
      end
    end)

    defp perform!(url, body) do
      Application.get_env(:slack, :web_http_client, Slack.Web.DefaultClient).post!(url, body)
    end

    defp get_token(%{token: token}), do: token
    defp get_token(_), do: Application.get_env(:slack, :api_token)

    if has_upload? do
      defp params(:upload, params, arguments) do
        file = List.first(arguments)

        params =
          Enum.map(params, fn {key, value} ->
            {"", to_string(value), {"form-data", [{"name", key}]}, []}
          end)

        {:multipart, params ++ [{:file, file, []}]}
      end
    end

    defp params(_, params, _), do: {:form, params}
  end
end)
