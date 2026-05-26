defmodule Slack.Mixfile do
  use Mix.Project

  @source_url "https://github.com/smstoslack/slack_kit"
  @version "0.24.0"

  def project do
    [
      app: :slack_kit,
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "SlackKit",
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.2"},
      {:websocket_client, "~> 1.6"},
      {:jason, "~> 1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
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
