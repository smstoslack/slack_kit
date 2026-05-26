# Regenerates the per-method JSON docs in lib/slack/web/docs/ by scraping
# https://docs.slack.dev/reference/methods.md and each linked method page.
#
#     mix run lib/mix/tasks/update_slack_api.exs                    # all methods
#     mix run lib/mix/tasks/update_slack_api.exs chat.postMessage   # subset
#
# The universal `token` argument is excluded — Slack.Web injects it at call time.

defmodule UpdateSlackApi do
  @index_url "https://docs.slack.dev/reference/methods.md"
  @out_dir "lib/slack/web/docs"
  @user_agent "slack_kit-doc-generator"

  @method_link_re ~r"\[([A-Za-z][\w.]*)\]\((https://docs\.slack\.dev/reference/methods/[\w.]+\.md)\)"
  @desc_re ~r/\*\*Description\*\*\s*([^\n]+)/
  @args_section_re ~r/##\s*Arguments\s*\{#arguments\}(.*?)(?=\n##\s|\z)/s
  @errors_section_re ~r/##\s*Errors\s*\{#errors\}(.*?)(?=\n##\s|\z)/s
  @arg_header_re ~r/\*\*`([^`]+)`\*\*(?:`([^`]+)`)?(Required|Optional)/
  @example_re ~r/_Example:_\s*`([^`]+)`/
  @default_re ~r/_Default:_\s*`([^`]+)`/
  @meta_split_re ~r/_(?:Example|Default):_/
  @subsection_re ~r/\n###\s.*\z/s
  @error_name_re ~r/^`([a-z][a-z0-9_]*)`$/
  @trailing_rule_re ~r/\s*\*\s*\*\s*\*\s*\z/
  @markdown_link_re ~r/\[([^\]]+)\]\([^)]+\)/

  @usage_section_re ~r/##\s*Usage info\s*\{#usage-info\}(.*?)(?=\n##\s|\z)/s
  @code_block_re ~r/```.*?```/s
  @heading_line_re ~r/^#+\s+.*$/m
  @hr_line_re ~r/^\s*\*\s*\*\s*\*\s*$/m
  @bullet_line_re ~r/\n[ \t]*\*[ \t]+/
  @sentence_split_re ~r/(?<=[.!?])\s+(?=[A-Z])/
  @arg_ref_re ~r/`([a-z][a-z0-9_]*)`/

  def run(args) do
    Application.ensure_all_started(:req)

    methods = list_methods() |> filter(args)
    IO.puts("Fetching #{length(methods)} methods...")

    File.mkdir_p!(@out_dir)

    methods
    |> Task.async_stream(&write_doc/1,
      max_concurrency: 8,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {:ok, name}} -> IO.puts("ok  #{name}")
      {:ok, {:error, name, reason}} -> IO.puts(:stderr, "err #{name}: #{reason}")
      {:exit, reason} -> IO.puts(:stderr, "exit: #{inspect(reason)}")
    end)
  end

  defp filter(methods, []), do: methods

  defp filter(methods, args) do
    set = MapSet.new(args)
    Enum.filter(methods, fn {name, _} -> name in set end)
  end

  defp list_methods do
    @index_url
    |> fetch!()
    |> then(&Regex.scan(@method_link_re, &1))
    |> Enum.reduce(%{}, fn [_, name, url], acc ->
      # Method names always contain a dot (e.g. chat.postMessage).
      # Skip incidental links to other reference pages.
      if String.contains?(name, "."), do: Map.put_new(acc, name, url), else: acc
    end)
    |> Enum.sort()
  end

  defp write_doc({name, url}) do
    try do
      data = url |> fetch!() |> parse_method_page()
      json = (data |> :json.format() |> IO.iodata_to_binary()) <> "\n"
      File.write!(Path.join(@out_dir, "#{name}.json"), json)
      {:ok, name}
    rescue
      e -> {:error, name, Exception.message(e)}
    end
  end

  defp fetch!(url) do
    %{body: body} = Req.get!(url, headers: [{"user-agent", @user_agent}])
    if is_binary(body), do: body, else: to_string(body)
  end

  defp parse_method_page(text) do
    %{
      "desc" => extract(text, @desc_re),
      "args" => parse_args(text),
      "errors" => parse_errors(text)
    }
  end

  defp extract(text, re) do
    case Regex.run(re, text) do
      [_, value] -> value |> String.trim() |> strip_links()
      _ -> ""
    end
  end

  defp strip_links(text), do: Regex.replace(@markdown_link_re, text, "\\1")

  defp parse_args(text) do
    case Regex.run(@args_section_re, text) do
      [_, section] ->
        section
        |> do_parse_args()
        |> Map.delete("token")
        |> apply_usage_constraints(text)

      _ ->
        %{}
    end
  end

  # Slack documents cross-argument constraints (e.g. "Exactly one of `team_id`
  # or `enterprise_id` is required") as prose in the Usage info section rather
  # than per-argument. Scan that section for sentences that reference one or
  # more known argument names in backticks and append each such sentence to the
  # matching arg's desc, so the constraint is visible at the call site.
  defp apply_usage_constraints(args, _text) when map_size(args) == 0, do: args

  defp apply_usage_constraints(args, text) do
    case Regex.run(@usage_section_re, text) do
      [_, usage] -> append_constraints(args, usage)
      _ -> args
    end
  end

  defp append_constraints(args, usage) do
    arg_names = MapSet.new(Map.keys(args))

    usage
    |> sanitize_usage()
    |> extract_sentences()
    |> Enum.reduce(args, fn sentence, acc ->
      case mentioned_args(sentence, arg_names) do
        # Cross-argument constraints reference two or more args by name in the
        # same sentence — skip single-arg mentions, which are usually just
        # descriptive prose covered by the arg's own description.
        mentioned when length(mentioned) >= 2 ->
          Enum.reduce(mentioned, acc, &append_constraint(&2, &1, sentence))

        _ ->
          acc
      end
    end)
  end

  defp sanitize_usage(usage) do
    usage
    |> then(&Regex.replace(@code_block_re, &1, ""))
    |> then(&Regex.replace(@heading_line_re, &1, ""))
    |> then(&Regex.replace(@hr_line_re, &1, ""))
    # Promote each bullet item to its own paragraph so the sentence splitter
    # treats them independently instead of merging the whole list.
    |> then(&Regex.replace(@bullet_line_re, &1, "\n\n"))
    |> String.replace("**", "")
    |> strip_links()
  end

  defp extract_sentences(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.flat_map(&split_paragraph/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_paragraph(paragraph) do
    paragraph
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(@sentence_split_re)
  end

  defp mentioned_args(sentence, arg_names) do
    @arg_ref_re
    |> Regex.scan(sentence, capture: :all_but_first)
    |> List.flatten()
    |> Enum.filter(&MapSet.member?(arg_names, &1))
    |> Enum.uniq()
  end

  defp append_constraint(args, arg_name, sentence) do
    Map.update!(args, arg_name, fn entry ->
      Map.update(entry, "desc", sentence, &append_sentence(&1, sentence))
    end)
  end

  defp append_sentence("", sentence), do: sentence

  defp append_sentence(desc, sentence) do
    separator = if String.ends_with?(desc, [".", "!", "?"]), do: " ", else: ". "
    desc <> separator <> sentence
  end

  defp do_parse_args(section) do
    section
    |> then(&Regex.replace(@arg_header_re, &1, "\u{0000}\\0"))
    |> String.split("\u{0000}", trim: true)
    |> Enum.flat_map(&parse_arg_chunk/1)
    |> Map.new()
  end

  defp parse_arg_chunk(chunk) do
    case Regex.run(@arg_header_re, chunk) do
      [matched, name, type, required] ->
        body =
          chunk
          |> String.replace_prefix(matched, "")
          |> then(&Regex.replace(@subsection_re, &1, ""))
          |> String.trim()

        desc =
          body
          |> String.split(@meta_split_re, parts: 2)
          |> hd()
          |> String.trim()
          |> strip_links()

        entry =
          %{"required" => required == "Required", "desc" => desc}
          |> maybe_put("type", non_empty(type))
          |> maybe_put("example", capture(@example_re, body))
          |> maybe_put("default", capture(@default_re, body))

        [{name, entry}]

      _ ->
        []
    end
  end

  defp parse_errors(text) do
    case Regex.run(@errors_section_re, text) do
      [_, section] -> do_parse_errors(section)
      _ -> %{}
    end
  end

  defp do_parse_errors(section) do
    {name, lines, errors} =
      section
      |> String.split("\n")
      |> Enum.reduce({nil, [], %{}}, &reduce_error_line/2)

    flush_error(name, lines, errors)
  end

  defp reduce_error_line(line, {current, lines, errors}) do
    stripped = String.trim(line)

    case Regex.run(@error_name_re, stripped) do
      [_, new_name] -> {new_name, [], flush_error(current, lines, errors)}
      _ -> accumulate_error_line(stripped, current, lines, errors)
    end
  end

  defp accumulate_error_line(_stripped, nil, lines, errors), do: {nil, lines, errors}
  defp accumulate_error_line("", current, lines, errors), do: {current, lines, errors}

  defp accumulate_error_line(stripped, current, lines, errors),
    do: {current, [stripped | lines], errors}

  defp flush_error(nil, _, errors), do: errors

  defp flush_error(name, lines, errors) do
    joined =
      lines
      |> Enum.reverse()
      |> Enum.join(" ")
      |> String.trim()
      |> then(&Regex.replace(@trailing_rule_re, &1, ""))
      |> String.trim()
      |> strip_links()

    if joined == "" or Map.has_key?(errors, name) do
      errors
    else
      Map.put(errors, name, joined)
    end
  end

  defp capture(re, text) do
    case Regex.run(re, text) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(string), do: string

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

UpdateSlackApi.run(System.argv())
