---
name: generate-slack-docs
description: Regenerate the JSON method docs in lib/slack/web/docs by scraping https://docs.slack.dev/reference/methods.md. Use when the Slack Web API has new or updated methods and the local docs need to be refreshed.
---

This skill regenerates the per-method JSON files in [lib/slack/web/docs/](lib/slack/web/docs/) that drive `Slack.Web` at runtime. Each JSON file contains the method's description, arguments, and documented errors, scraped from the canonical Slack docs.

The work is done by the script at [lib/mix/tasks/update_slack_api.exs](lib/mix/tasks/update_slack_api.exs). It uses Req (already a project dep) for fetching and Jason for serialization, loaded automatically by `mix run`.

## How to run

From the project root:

```
mix run lib/mix/tasks/update_slack_api.exs
```

To regenerate only specific methods (useful for testing parser changes or partial updates):

```
mix run lib/mix/tasks/update_slack_api.exs chat.postMessage conversations.list
```

## Output format

Each file matches the existing shape:

```json
{
  "args": {
    "channel": {
      "required": true,
      "type": "string",
      "example": "C1234567890",
      "desc": "..."
    }
  },
  "desc": "Short, one-line method description.",
  "errors": {
    "channel_not_found": "Value passed for `channel` was invalid."
  }
}
```

Notes on the shape:

- The universal `token` argument is excluded — it's injected by `Slack.Web` at call time, so per-method docs shouldn't repeat it.
- `type`, `example`, and `default` are only emitted when the upstream page provides them.
- `required` is always emitted as a boolean.
- File names use the canonical camelCase method name from the index (e.g. `chat.postMessage.json`), even though the upstream URL is lowercased.

## After running

1. Run `git status` and `git diff` to see what changed. Expect many new files (the Slack API has grown a lot since the existing docs were generated) and updates to most existing ones.
2. Spot-check a few diffs — particularly methods you know the team uses — to make sure the parser didn't mangle anything. Pay attention to:
   - Multi-paragraph descriptions getting truncated.
   - Errors with backticked tokens in their descriptions confusing the parser.
   - Methods whose page has no `## Errors` section (admin.* methods often don't) — these should produce `"errors": {}`.
3. If a method file looks wrong, fetch its source page manually (`curl -sL https://docs.slack.dev/reference/methods/<name>.md`) and compare against the parser output to decide whether to patch the task or hand-fix the JSON.

## When the parser breaks

The upstream docs are markdown rendered from Slack's internal API spec, and the format occasionally drifts. If a fresh run produces obviously-wrong output for many methods, the layout has probably changed. Open [lib/mix/tasks/update_slack_api.exs](lib/mix/tasks/update_slack_api.exs) and check:

- `parse_method_page/1` — section anchors (`## Arguments {#arguments}`, `## Errors {#errors}`).
- `do_parse_args/1` — the `**\`name\`**\`type\`Required|Optional` header pattern and the `_Example:_` / `_Default:_` markers.
- `do_parse_errors/1` — the reducer that pairs error names with descriptions.

Fix the parser rather than hand-editing dozens of JSON files.
