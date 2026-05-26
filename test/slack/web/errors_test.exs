defmodule Slack.Web.ErrorsTest do
  use ExUnit.Case, async: true

  test "common/0 returns the canonical error map" do
    common = Slack.Web.Errors.common()

    assert is_map(common)
    assert map_size(common) > 0
    assert Map.has_key?(common, "invalid_auth")
    assert Map.has_key?(common, "ratelimited")
    assert Map.has_key?(common, "not_authed")
  end

  test "names/0 returns a MapSet of the common error codes" do
    names = Slack.Web.Errors.names()

    assert MapSet.member?(names, "invalid_auth")
    assert MapSet.equal?(names, MapSet.new(Map.keys(Slack.Web.Errors.common())))
  end

  test "no per-endpoint JSON file lists a common error" do
    common = Slack.Web.Errors.names()
    docs_dir = Path.join([File.cwd!(), "lib", "slack", "web", "docs"])

    offenders =
      docs_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.flat_map(fn file ->
        errors =
          Path.join(docs_dir, file)
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

  test "moduledoc embeds the common error list" do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Slack.Web.Errors)

    assert moduledoc =~ "* `invalid_auth`"
    assert moduledoc =~ "* `ratelimited`"
  end
end
