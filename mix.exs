defmodule Slack.Mixfile do
  use Mix.Project

  @source_url "https://github.com/smstoslack/slack_kit"
  @version "0.24.0"

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
      {:castore, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:junit_formatter, "~> 3.4", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:plug_cowboy, "~> 2.8", only: :test}
    ]
  end

  def docs do
    [
      extras: [
        {:"LICENSE.md", [title: "License"]},
        {:"README.md", [title: "Overview"]},
        "guides/token_generation_instructions.md"
      ],
      main: "readme",
      source_url: @source_url,
      assets: "guides/assets",
      extra_section: "GUIDES",
      formatters: ["html"]
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
