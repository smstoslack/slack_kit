defmodule Slack.Web.CommonErrorsTest do
  use ExUnit.Case, async: true

  @common_errors_path Path.join([
                        File.cwd!(),
                        "lib",
                        "slack",
                        "web",
                        "common_errors.json"
                      ])

  @markdown_path Path.join([File.cwd!(), "guides", "common_errors.md"])
  @docs_dir Path.join([File.cwd!(), "lib", "slack", "web", "docs"])

  test "no per-endpoint JSON file lists a common error" do
    common = common_error_names()

    offenders =
      @docs_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.flat_map(fn file ->
        errors =
          @docs_dir
          |> Path.join(file)
          |> File.read!()
          |> JSON.decode!()
          |> Map.get("errors", %{})
          |> Kernel.||(%{})

        Enum.flat_map(Map.keys(errors), fn name ->
          if MapSet.member?(common, name), do: [{file, name}], else: []
        end)
      end)

    assert offenders == [],
           "Common errors leaked into per-endpoint docs:\n" <>
             Enum.map_join(offenders, "\n", fn {f, n} -> "  #{f}: #{n}" end)
  end

  test "markdown guide lists every common error from the JSON" do
    markdown = File.read!(@markdown_path)

    Enum.each(common_error_names(), fn name ->
      assert markdown =~ "`#{name}`",
             "expected #{@markdown_path} to mention `#{name}`"
    end)
  end

  defp common_error_names do
    @common_errors_path
    |> File.read!()
    |> JSON.decode!()
    |> Map.keys()
    |> MapSet.new()
  end
end
