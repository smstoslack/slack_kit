defmodule Slack.Web.DocumentationTest do
  use ExUnit.Case
  alias Slack.Web.Documentation

  test "it returns a proper keyword list" do
    doc = %Documentation{required_params: [:channel, :text]}

    argument_value_keyword_list = Documentation.arguments_with_values(doc)
    assert argument_value_keyword_list === [text: {:text, [], nil}, channel: {:channel, [], nil}]
  end

  describe "new/2" do
    test "takes a documentation and filename, returns a module & function description" do
      file_content = %{
        "desc" => "Gets information about the current team.",
        "args" => %{},
        "errors" => %{}
      }

      doc = Documentation.new(file_content, "team.info.json")

      assert doc.module == "team"
      assert doc.endpoint == "team.info"
      assert doc.function == :info
      assert doc.desc == "Gets information about the current team."
      assert doc.required_params == []
      assert doc.optional_params == []
      assert doc.errors == %{}
      assert doc.raw == file_content

      module_functions = Slack.Web.Team.__info__(:functions)

      assert {:info, 0} in module_functions
      assert {:info, 1} in module_functions
    end

    test "extracts required and optional params from the args map" do
      file_content = %{
        "desc" => "Sends a message.",
        "args" => %{
          "channel" => %{"required" => true, "desc" => "channel id"},
          "text" => %{"required" => true, "desc" => "the text", "example" => "hi"},
          "as_user" => %{"required" => false, "desc" => "post as user"}
        },
        "errors" => %{"channel_not_found" => "Channel was not found."}
      }

      doc = Documentation.new(file_content, "chat.postMessage.json")

      assert Enum.sort(doc.required_params) == [:channel, :text]
      assert doc.optional_params == [:as_user]
    end

    test "treats files without args as having no params" do
      doc = Documentation.new(%{"desc" => "no args"}, "team.info.json")
      assert doc.required_params == []
      assert doc.optional_params == []
    end
  end

  describe "to_doc_string/1" do
    test "includes the description, params, and errors" do
      file_content = %{
        "desc" => "Post a message. See [the docs](/concepts) for details.",
        "args" => %{
          "channel" => %{"required" => true, "desc" => "channel id", "example" => "C123"},
          "text" => %{"required" => true, "desc" => "the text"},
          "as_user" => %{"required" => false, "desc" => "post as user", "example" => "true"}
        },
        "errors" => %{"channel_not_found" => "Channel was not found."}
      }

      doc = Documentation.new(file_content, "chat.postMessage.json")
      output = Documentation.to_doc_string(doc)

      assert output =~ "Post a message"
      assert output =~ "Required Params"
      assert output =~ "* `channel`"
      assert output =~ "ex: `C123`"
      assert output =~ "Optional Params"
      assert output =~ "* `as_user`"
      assert output =~ "Errors the API can return"
      assert output =~ "* `channel_not_found`"

      assert output =~
               "See the [Common Errors](common_errors.md) guide for errors returned by every Web API method."

      refute output =~ "(/concepts)"
      assert output =~ "the docs"
    end

    test "links to the Common Errors guide even when the endpoint has no specific errors" do
      file_content = %{
        "desc" => "Plain endpoint.",
        "args" => %{},
        "errors" => %{}
      }

      output = Documentation.to_doc_string(Documentation.new(file_content, "team.info.json"))

      refute output =~ "Errors the API can return"

      assert output =~
               "See the [Common Errors](common_errors.md) guide for errors returned by every Web API method."
    end

    test "omits sections when there are no params or errors" do
      doc = Documentation.new(%{"desc" => "Plain endpoint."}, "team.info.json")
      output = Documentation.to_doc_string(doc)

      assert output =~ "Plain endpoint."
      refute output =~ "Required Params"
      refute output =~ "Optional Params"
      refute output =~ "Errors the API can return"
      refute output =~ "Scopes"
      refute output =~ "Rate limit"

      assert output =~
               "See the [Common Errors](common_errors.md) guide for errors returned by every Web API method."
    end

    test "renders scopes grouped by token type with links" do
      file_content = %{
        "desc" => "Sends a message.",
        "scopes" => %{
          "bot" => [
            %{
              "name" => "chat:write",
              "url" => "https://docs.slack.dev/reference/scopes/chat.write"
            }
          ],
          "user" => [
            %{
              "name" => "chat:write",
              "url" => "https://docs.slack.dev/reference/scopes/chat.write"
            }
          ]
        }
      }

      output =
        Documentation.to_doc_string(Documentation.new(file_content, "chat.postMessage.json"))

      assert output =~ "> #### API reference {: .info}"
      assert output =~ "> **Scopes**"
      assert output =~ "> _Bot token_"
      assert output =~ "> _User token_"
      assert output =~ "> * [`chat:write`](https://docs.slack.dev/reference/scopes/chat.write)"
    end

    test "renders 'No scopes required' when scopes is empty" do
      doc = Documentation.new(%{"desc" => "x", "scopes" => %{}}, "auth.test.json")
      output = Documentation.to_doc_string(doc)

      assert output =~ "> #### API reference {: .info}"
      assert output =~ "> **Scopes:** _No scopes required_"
    end

    test "renders scopes and rate limit in a single info admonition" do
      file_content = %{
        "desc" => "x",
        "scopes" => %{
          "bot" => [
            %{
              "name" => "users:read",
              "url" => "https://docs.slack.dev/reference/scopes/users.read"
            }
          ]
        },
        "rate_limit" => %{
          "label" => "Tier 2: 20+ per minute",
          "url" => "https://docs.slack.dev/apis/web-api/rate-limits"
        }
      }

      output = Documentation.to_doc_string(Documentation.new(file_content, "users.list.json"))

      # Only one admonition opens.
      assert output |> String.split("> #### API reference {: .info}") |> length() == 2

      assert output =~ "> **Scopes**"
      assert output =~ "> _Bot token_"

      assert output =~
               "> **Rate limit:** [Tier 2: 20+ per minute](https://docs.slack.dev/apis/web-api/rate-limits)"
    end

    test "omits the admonition entirely when neither scopes nor rate_limit are present" do
      doc = Documentation.new(%{"desc" => "Legacy endpoint."}, "legacy.method.json")
      output = Documentation.to_doc_string(doc)

      refute output =~ "API reference"
      refute output =~ "{: .info}"
    end
  end

  describe "example/1" do
    test "returns formatted example when present" do
      assert Documentation.example(%{"example" => "abc"}) == "ex: `abc`"
    end

    test "returns empty string when missing" do
      assert Documentation.example(%{}) == ""
      assert Documentation.example(nil) == ""
    end
  end

  describe "new/2 versioned endpoints" do
    test "accepts versioned endpoints" do
      file_content =
        "#{__DIR__}/../../../priv/docs/methods/oauth.v2.access.json"
        |> File.read!()
        |> JSON.decode!()

      doc = Documentation.new(file_content, "oauth.v2.access.json")

      assert doc.module == "oauth.v2"
      assert doc.endpoint == "oauth.v2.access"
      assert doc.function == :access

      module_functions = Slack.Web.Oauth.V2.__info__(:functions)

      access_arities =
        for {:access, arity} <- module_functions, do: arity

      assert access_arities != []
    end
  end
end
