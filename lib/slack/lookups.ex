defmodule Slack.Lookups do
  @moduledoc """
  Utility functions for looking up slack state information.
  """

  require Logger

  @username_warning """
  Referencing "@USER_NAME" is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """

  @doc ~S"""
  Turns a string like `"@USER_NAME"` into the ID that Slack understands (`"U…"`).

  NOTE: Referencing `"@USER_NAME"` is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """
  def lookup_user_id("@" <> user_name, slack) do
    Logger.warning(@username_warning)

    slack.users
    |> Map.values()
    |> Enum.find(%{}, fn user ->
      user.name == user_name || user.profile.display_name == user_name
    end)
    |> Map.get(:id)
  end

  @doc ~S"""
  Turns a string like `"@USER_NAME"` or a user ID (`"U…"`) into the ID for the
  direct message channel of that user (`"D…"`).  `nil` is returned if a direct
  message channel has not yet been opened.

  NOTE: Referencing `"@USER_NAME"` is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """
  def lookup_direct_message_id("@" <> _user_name = user, slack) do
    user
    |> lookup_user_id(slack)
    |> lookup_direct_message_id(slack)
  end

  def lookup_direct_message_id(user_id, slack) do
    slack.ims
    |> Map.values()
    |> Enum.find(%{}, fn direct_message -> direct_message.user == user_id end)
    |> Map.get(:id)
  end

  @doc ~S"""
  Turns a string like `"#CHANNEL_NAME"` into the ID that Slack understands
  (`"C…"`) if a public channel,
  (`"G…"`) if a group/private channel.
  """
  def lookup_channel_id("#" <> channel_name, slack) do
    channel =
      find_channel_by_name(slack.channels, channel_name) ||
        find_channel_by_name(slack.groups, channel_name) || %{}

    Map.get(channel, :id)
  end

  @doc ~S"""
  Turns a Slack user ID (`"U…"`), direct message ID (`"D…"`), or bot ID (`"B…"`)
  into a string in the format "@USER_NAME".

  NOTE: Referencing `"@USER_NAME"` is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """
  def lookup_user_name("D" <> _id = direct_message_id, slack) do
    lookup_user_name(slack.ims[direct_message_id].user, slack)
  end

  def lookup_user_name("U" <> _id = user_id, slack) do
    find_username_by_id(user_id, slack)
  end

  def lookup_user_name("W" <> _id = user_id, slack) do
    find_username_by_id(user_id, slack)
  end

  def lookup_user_name("B" <> _id = bot_id, slack) do
    Logger.warning(@username_warning)
    "@" <> slack.bots[bot_id].name
  end

  @doc ~S"""
  Turns a Slack channel ID (`"C…"`) or a Slack private channel ID (`"G…"`) into
  a string in the format "#CHANNEL_NAME".
  """
  def lookup_channel_name("C" <> _id = channel_id, slack) do
    "#" <> slack.channels[channel_id].name
  end

  def lookup_channel_name("G" <> _id = channel_id, slack) do
    "#" <> slack.groups[channel_id].name
  end

  defp find_channel_by_name(nested_map, name) do
    Enum.find_value(nested_map, fn {_id, map} -> if map.name == name, do: map, else: nil end)
  end

  defp find_username_by_id(user_id, slack) do
    Logger.warning(@username_warning)
    "@" <> slack.users[user_id].name
  end
end
