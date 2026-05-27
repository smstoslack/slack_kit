defmodule Slack.Mixfile do
  use Mix.Project

  @source_url "https://github.com/smstoslack/slack_kit"
  @version "1.0.0-alpha.0"

  def project do
    [
      app: :slack_kit,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "SlackKit",
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:mint_web_socket, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:junit_formatter, "~> 3.4", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:plug_cowboy, "~> 2.8", only: :test}
    ]
  end

  def docs do
    [
      extras: [
        {:"README.md", [title: "Overview"]},
        "guides/configuration.md",
        "guides/token_generation_instructions.md",
        "guides/common_errors.md",
        {:"CHANGELOG.md", [title: "Changelog"]},
        {:"LICENSE.md", [title: "License"]}
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      assets: %{"guides/assets" => "assets"},
      extra_section: "GUIDES",
      formatters: ["html"],
      nest_modules_by_prefix: [Slack.Web, Slack.Web.Admin],
      markdown_processor: {ExDoc.Markdown.Earmark, [breaks: true]},
      groups_for_modules: [
        "Real-Time Messaging": [
          Slack,
          Slack.Bot,
          Slack.State,
          Slack.Lookups,
          Slack.Sends,
          Slack.WebSocketClient
        ],
        "Web API": [
          Slack.Web.Client,
          Slack.Web.DefaultClient,
          Slack.Web.Documentation,
          Slack.Web.Errors
        ],
        "Web API Methods": [~r/^Slack\.Web($|\.)/]
      ]
    ]
  end

  defp package do
    [
      description: "A Slack Web & Real Time Messaging API client.",
      maintainers: ["Samuel Gordalina"],
      licenses: ["MIT"],
      links: %{
        GitHub: @source_url
      }
    ]
  end
end
