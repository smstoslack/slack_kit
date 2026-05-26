defmodule Slack.State do
  @moduledoc """
  Workspace snapshot maintained for a running `Slack.Bot`.

  Each callback in a module that does `use Slack` receives a `%Slack.State{}`
  as its `slack` argument. The struct starts from the payload Slack returns on
  `rtm.start` and is rolled forward by `update/2` as each RTM event arrives,
  so the maps you read inside a callback always reflect the latest known
  state of the workspace.

  ## Fields

  | Field      | Description                                                                  |
  | ---------- | ---------------------------------------------------------------------------- |
  | `:me`      | The bot's own identity (id, name, profile).                                  |
  | `:team`    | The workspace's identity (id, name, domain).                                 |
  | `:bots`    | Map of `bot_id => bot` for bots known to the workspace.                      |
  | `:channels`| Map of `channel_id => channel` for public channels.                          |
  | `:groups`  | Map of `channel_id => channel` for private channels.                         |
  | `:users`   | Map of `user_id => user`. Includes `:presence` as it's reported.             |
  | `:ims`     | Map of `channel_id => im` for open direct-message channels.                  |
  | `:process` | PID of the `Slack.Bot` GenServer driving the WebSocket.                      |
  | `:client`  | Module implementing the WebSocket transport — used by `Slack.Sends`.         |
  | `:token`   | The bot's Slack API token.                                                   |

  All entity maps use Slack's string IDs as keys. The values are atom-keyed
  maps mirroring the [Slack API types](https://api.slack.com/types) — for
  example `slack.users["U123"].profile.display_name`.

  ## Access

  `Slack.State` implements the `Access` behaviour and is keyed like a map, so
  the standard `get_in`/`put_in`/`update_in` helpers work directly against it:

      get_in(slack, [:channels, "C123", :name])
      put_in(slack, [:users, "U123", :presence], "away")

  ## Updating from RTM events

  `update/2` pattern-matches on `event.type` and folds the event into the
  state. Supporting a new RTM event type means adding another `update/2`
  clause here. Unrecognised events fall through to a catch-all and leave the
  state untouched.
  """

  @behaviour Access

  def fetch(client, key)
  defdelegate fetch(client, key), to: Map

  def get(client, key, default)
  defdelegate get(client, key, default), to: Map

  def get_and_update(client, key, function)
  defdelegate get_and_update(client, key, function), to: Map

  def pop(client, key)
  defdelegate pop(client, key), to: Map

  defstruct [
    :process,
    :client,
    :token,
    :me,
    :team,
    bots: %{},
    channels: %{},
    groups: %{},
    users: %{},
    ims: %{}
  ]

  @type t :: %__MODULE__{
          process: pid() | nil,
          client: module() | nil,
          token: String.t() | nil,
          me: map() | nil,
          team: map() | nil,
          bots: map(),
          channels: map(),
          groups: map(),
          users: map(),
          ims: map()
        }

  defp safe_map_getter(key) do
    Access.key(key, %{})
  end

  defp safe_list_getter(key) do
    Access.key(key, [])
  end

  @doc """
  Folds a single RTM event into `slack`, returning the updated state.

  Recognised event types include `channel_created`, `channel_joined`,
  `channel_left`, `channel_rename`, `channel_archive`, `channel_unarchive`,
  their `group_*` equivalents, `team_rename`, `team_join`, `user_change`,
  `presence_change`, `bot_added`, `bot_changed`, `im_created`, and the
  `message` subtypes that signal topic/join/leave changes. Any other event is
  returned unchanged.
  """
  @spec update(map(), t()) :: t()
  def update(%{type: "channel_created", channel: channel}, slack) do
    put_in(slack, [:channels, channel.id], channel)
  end

  def update(%{type: "channel_joined", channel: channel}, slack) do
    slack
    |> put_in([:channels, channel.id], channel)
    |> put_in([:channels, channel.id, :is_member], true)
  end

  def update(%{type: "group_joined", channel: channel}, slack) do
    put_in(slack, [:groups, channel.id], channel)
  end

  def update(%{type: "channel_left", channel: channel_id}, slack) do
    put_in(slack, [:channels, channel_id, :is_member], false)
  end

  def update(%{type: "group_left", channel: channel}, slack) do
    update_in(slack, [:groups], &Map.delete(&1, channel))
  end

  Enum.map(["channel", "group"], fn type ->
    plural_atom = String.to_atom(type <> "s")

    def update(%{type: unquote(type <> "_rename"), channel: channel}, slack) do
      put_in(slack, [unquote(plural_atom), safe_map_getter(channel.id), :name], channel.name)
    end

    def update(%{type: unquote(type <> "_archive"), channel: channel}, slack) do
      put_in(slack, [unquote(plural_atom), safe_map_getter(channel), :is_archived], true)
    end

    def update(%{type: unquote(type <> "_unarchive"), channel: channel}, slack) do
      put_in(slack, [unquote(plural_atom), safe_map_getter(channel), :is_archived], false)
    end

    def update(
          %{
            type: "message",
            subtype: unquote(type <> "_topic"),
            channel: channel,
            user: user,
            topic: topic
          },
          slack
        ) do
      put_in(slack, [unquote(plural_atom), safe_map_getter(channel), :topic], %{
        creator: user,
        last_set: System.system_time(:second),
        value: topic
      })
    end

    def update(
          %{type: "message", subtype: unquote(type <> "_join"), channel: channel, user: user},
          slack
        ) do
      update_in(
        slack,
        [unquote(plural_atom), safe_map_getter(channel), safe_list_getter(:members)],
        &Enum.uniq([user | &1])
      )
    end

    def update(
          %{type: "message", subtype: unquote(type <> "_leave"), channel: channel, user: user},
          slack
        ) do
      update_in(
        slack,
        [unquote(plural_atom), safe_map_getter(channel), safe_list_getter(:members)],
        &(&1 -- [user])
      )
    end
  end)

  def update(%{type: "team_rename", name: name}, slack) do
    put_in(slack, [:team, :name], name)
  end

  def update(%{type: "presence_change", user: user, presence: presence}, slack) do
    put_in(slack, [:users, user, :presence], presence)
  end

  def update(%{type: "presence_change", users: users, presence: presence}, slack) do
    Enum.reduce(users, slack, fn user, acc ->
      put_in(acc, [:users, user, :presence], presence)
    end)
  end

  def update(%{type: "team_join", user: user}, slack) do
    put_in(slack, [:users, user.id], user)
  end

  def update(%{type: "user_change", user: user}, slack) do
    update_in(slack, [:users, Access.key(user.id, %{})], &Map.merge(&1, user))
  end

  Enum.map(["bot_added", "bot_changed"], fn type ->
    def update(%{type: unquote(type), bot: bot}, slack) do
      put_in(slack, [:bots, bot.id], bot)
    end
  end)

  def update(%{type: "im_created", channel: channel}, slack) do
    put_in(slack, [:ims, channel.id], channel)
  end

  def update(%{type: _type}, slack) do
    slack
  end
end
