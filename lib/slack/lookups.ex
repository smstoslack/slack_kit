defmodule Slack.Lookups do
  @moduledoc """
  Translates between Slack's IDs and human-friendly names.

  Slack's RTM events almost always carry IDs (`"U…"`, `"C…"`, `"G…"`, `"D…"`,
  `"B…"`) rather than display names; these helpers resolve them either
  direction against the live `Slack.State` your bot holds. All functions are
  imported into modules that `use Slack`, so you can call them unqualified
  from within callbacks.

  The functions that accept `"@USER_NAME"` / `"#CHANNEL_NAME"` strings are
  convenient but slow (linear scan over `slack.users` or `slack.channels`).
  Prefer raw IDs in hot paths.

  > #### Username references are deprecated {: .warning}
  >
  > Slack deprecated `@username` references in 2017; see the
  > [changelog](https://api.slack.com/changelog/2017-09-the-one-about-usernames).
  > Functions that accept them log a warning on each call and may be removed
  > in a future major version.
  """

  require Logger

  @username_warning """
  Referencing "@USER_NAME" is deprecated, and should not be used.
  For more information see https://api.slack.com/changelog/2017-09-the-one-about-usernames
  """

  @type slack :: Slack.State.t()

  @doc ~S"""
  Resolves a `"@USER_NAME"` string to a user ID (`"U…"`).

  Returns `nil` if no user with that name is present in `slack.users`.
  Deprecated; see the module docs.
  """
  @spec lookup_user_id(String.t(), slack) :: String.t() | nil
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
  Resolves a user reference to its DM channel ID (`"D…"`).

  Accepts either a user ID (`"U…"`) or a `"@USER_NAME"` string (deprecated).
  Returns `nil` if a DM channel with that user has not been opened yet —
  `Slack.Sends.send_message/3` will open one transparently in that case.
  """
  @spec lookup_direct_message_id(String.t(), slack) :: String.t() | nil
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
  Resolves a `"#CHANNEL_NAME"` string to its ID.

  Returns the channel's ID as `"C…"` for a public channel or `"G…"` for a
  private channel/group. Returns `nil` if no channel with that name is known
  to `slack`.
  """
  @spec lookup_channel_id(String.t(), slack) :: String.t() | nil
  def lookup_channel_id("#" <> channel_name, slack) do
    channel =
      find_channel_by_name(slack.channels, channel_name) ||
        find_channel_by_name(slack.groups, channel_name) || %{}

    Map.get(channel, :id)
  end

  @doc ~S"""
  Resolves a Slack ID to a `"@USER_NAME"` string.

  Accepts a user ID (`"U…"` or `"W…"`), a DM channel ID (`"D…"` — looked up
  via the user on the other side of the DM), or a bot ID (`"B…"`). Returns
  the name prefixed with `@`. Deprecated; see the module docs.
  """
  @spec lookup_user_name(String.t(), slack) :: String.t()
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
  Resolves a Slack channel ID to a `"#CHANNEL_NAME"` string.

  Accepts a public channel ID (`"C…"`) or a private channel ID (`"G…"`).
  Returns the name prefixed with `#`.
  """
  @spec lookup_channel_name(String.t(), slack) :: String.t()
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
