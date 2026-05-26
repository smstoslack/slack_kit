defmodule Slack.JSON do
  @moduledoc false

  def atomize_keys(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)

  def atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  def atomize_keys(other), do: other
end
