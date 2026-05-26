defmodule Slack.Web.Documentation do
  @moduledoc false

  defstruct [
    :endpoint,
    :module,
    :function,
    :desc,
    :required_params,
    :optional_params,
    :errors,
    :raw
  ]

  def new(documentation, file_name) do
    endpoint = String.replace(file_name, ".json", "")

    {module_name, function_name} = parse_endpoint(endpoint)

    %__MODULE__{
      module: module_name,
      endpoint: endpoint,
      function: function_name |> Macro.underscore() |> String.to_atom(),
      desc: documentation["desc"],
      required_params: get_required_params(documentation),
      optional_params: get_optional_params(documentation),
      errors: documentation["errors"],
      raw: documentation
    }
  end

  def arguments(documentation) do
    documentation.required_params
    |> Enum.map(&Macro.var(&1, nil))
  end

  def arguments_with_values(documentation) do
    documentation
    |> arguments()
    |> Enum.reduce([], fn var = {arg, _, _}, acc ->
      [{arg, var} | acc]
    end)
  end

  def to_doc_string(documentation) do
    [
      documentation.desc,
      facts_docs(documentation),
      required_params_docs(documentation),
      optional_params_docs(documentation),
      errors_docs(documentation)
    ]
    |> Enum.join("\n")
    |> strip_relative_links()
  end

  @relative_link_re ~r/\[([^\]]+)\]\(\/[^)]*\)/
  defp strip_relative_links(text), do: Regex.replace(@relative_link_re, text, "\\1")

  defp facts_docs(%__MODULE__{endpoint: endpoint, raw: raw}) when is_map(raw) do
    lines =
      rate_limit_lines(Map.get(raw, "rate_limit")) ++
        scope_lines(Map.get(raw, "scopes")) ++
        [""] ++
        reference_lines(endpoint)

    admonition("API reference", drop_trailing_blanks(lines))
  end

  defp reference_lines(endpoint) do
    [
      "[View on docs.slack.dev ↗](https://docs.slack.dev/reference/methods/#{String.downcase(endpoint)})"
    ]
  end

  defp scope_lines(nil), do: []
  defp scope_lines(scopes) when scopes == %{}, do: ["**Scopes:** _No scopes required_", ""]

  defp scope_lines(scopes) do
    ["**Scopes:**", "" | scope_group_lines(scopes)]
  end

  defp scope_group_lines(scopes) do
    ["bot", "user", "app"]
    |> Enum.flat_map(&scope_group_section(&1, Map.get(scopes, &1)))
  end

  defp scope_group_section(_key, nil), do: []
  defp scope_group_section(_key, []), do: []

  defp scope_group_section(key, list) do
    items =
      Enum.map_join(list, ", ", fn %{"name" => name, "url" => url} -> "[`#{name}`](#{url})" end)

    ["* _#{scope_token_label(key)}_: #{items}"]
  end

  defp scope_token_label("bot"), do: "Bot token"
  defp scope_token_label("user"), do: "User token"
  defp scope_token_label("app"), do: "App token"

  defp rate_limit_lines(%{"label" => label, "url" => url}),
    do: ["**Rate limit:** [#{label}](#{url})"]

  defp rate_limit_lines(_), do: []

  # ExDoc admonition info block — a markdown blockquote with `{: .info}`.
  # Body lines are quoted; empty lines become bare `>` so the block stays
  # contiguous in the rendered output.
  defp admonition(title, body_lines) do
    quoted = Enum.map_join(body_lines, "\n", &("> " <> &1))
    "\n> #### #{title} {: .info}\n>\n" <> quoted <> "\n"
  end

  defp drop_trailing_blanks(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp required_params_docs(%__MODULE__{required_params: []}), do: ""

  defp required_params_docs(documentation) do
    get_param_docs_for(documentation, :required_params, "Required Params")
  end

  defp optional_params_docs(%__MODULE__{optional_params: []}), do: ""

  defp optional_params_docs(documentation) do
    get_param_docs_for(documentation, :optional_params, "Optional Params")
  end

  defp get_param_docs_for(documentation, field, title) do
    Map.get(documentation, field)
    |> Enum.reduce("\n#{title}\n", fn param, doc ->
      meta = get_in(documentation.raw, ["args", to_string(param)])
      doc <> "* `#{param}` - #{meta["desc"]} #{example(meta)}\n"
    end)
  end

  def example(%{"example" => example}) do
    "ex: `#{example}`"
  end

  def example(_meta), do: ""

  @common_errors_footer "\nSee the [Common Errors](common_errors.md) guide for errors returned by every Web API method.\n"

  defp errors_docs(%__MODULE__{errors: nil}), do: @common_errors_footer
  defp errors_docs(%__MODULE__{errors: errors}) when errors == %{}, do: @common_errors_footer

  defp errors_docs(%__MODULE__{errors: errors}) do
    errors
    |> Enum.reduce("\nErrors the API can return:\n", fn {error, desc}, doc ->
      doc <> "* `#{error}` - #{desc}\n"
    end)
    |> Kernel.<>(@common_errors_footer)
  end

  defp get_required_params(json), do: get_params_with_required(json, true)
  defp get_optional_params(json), do: get_params_with_required(json, false)

  defp get_params_with_required(%{"args" => args}, required) do
    args
    |> Enum.filter(fn {_, meta} ->
      if required do
        meta["required"]
      else
        !meta["required"]
      end
    end)
    |> Enum.map(fn {name, _meta} ->
      name |> String.to_atom()
    end)
  end

  defp get_params_with_required(_json, _required) do
    []
  end

  @spec parse_endpoint(String.t()) :: {String.t(), String.t()}
  defp parse_endpoint(endpoint) do
    {module_name, function_name} =
      endpoint
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.find_index(&(&1 == "."))
      |> then(&String.split_at(endpoint, -&1))

    {String.replace_suffix(module_name, ".", ""), function_name}
  end
end
