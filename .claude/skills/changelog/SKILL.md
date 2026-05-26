---
name: changelog
description: Add an entry to the "## Next" section of CHANGELOG.md, creating that section if it doesn't exist. Use when the user wants to record a change, update the changelog, or note a breaking/feature/fix in CHANGELOG.md.
---

This skill appends a bullet to the unreleased `## Next` section of [CHANGELOG.md](../../../CHANGELOG.md). It is the single place to record a change between releases — released sections (`## 0.24.0`, etc.) are immutable.

## Where the entry goes

- The file always starts with the literal heading `# Changelog`.
- `## Next` lives directly under `# Changelog`, separated by one blank line on each side.
- If `## Next` does not exist, create it between `# Changelog` and the most recent released version heading (`## X.Y.Z`).
- Released version sections are never edited by this skill — only `## Next`.

The shape to preserve:

```
# Changelog

## Next

- <entries go here>

## 0.24.0

- Dependency updates.
```

## Entry rules

Match the style of existing entries:

1. **Bullet format:** `- ` (dash + single space), one entry per line, no nested bullets.
2. **Sentence case** with a trailing period. Start with an imperative verb (`Add`, `Replace`, `Rewrite`, `Remove`, `Fix`, `Bump`, `Drop`).
3. **Backticks for code identifiers** — package names (`jason`, `req`), module names (`Slack.Web`), config keys (`:rtm_module`), function names (`start_link/4`), file paths.
4. **Breaking changes:** prefix the bullet with `**Breaking:** ` (bold marker, colon, single space) before the verb. Examples: `- **Breaking:** Requires Elixir 1.18.`
5. **One change per bullet.** If a single PR contains a breaking change and an unrelated additive change, write two bullets.
6. **No PR numbers, no author attributions, no issue links** — the git history carries those.
7. **No section sub-headings** (no `### Added` / `### Changed`). It's a flat bulleted list inside `## Next`.
8. **Where to insert a new entry:**
   - Non-breaking change → append to the bottom of the list.
   - Breaking change, when breaking entries already exist → append directly after the last existing `**Breaking:**` bullet (bottom of the breaking-changes group).
   - Breaking change, when no breaking entries exist yet → insert at the top of the list, above all non-breaking bullets.

## How to apply

1. Read [CHANGELOG.md](../../../CHANGELOG.md).
2. If `## Next` is missing, insert it (with surrounding blank lines) immediately after the `# Changelog` heading.
3. Insert the new bullet under `## Next` following the placement rules in rule 8 above.
4. Do not touch anything below `## Next`.

## Examples

Adding a non-breaking change to an existing `## Next`:

```
## Next

- **Breaking:** Requires Elixir 1.18.
- Replace `httpoison` with `req` as the HTTP client.
- Add `Slack.Web.Reactions.add/2` helper.   ← new entry appended at end
```

Creating `## Next` when it doesn't exist:

```
# Changelog

## Next

- Add `Slack.Web.Reactions.add/2` helper.

## 0.24.0

- Dependency updates.
```

Recording the first breaking change when only non-breaking entries exist — insert it at the top of the list, above the non-breaking bullets:

```
## Next

- **Breaking:** Drop support for OTP 26.   ← first breaking change, goes to top
- Add `Slack.Web.Reactions.add/2` helper.
- Bump `req` to 0.6.
```

Recording an additional breaking change when breaking entries already exist — append after the last `**Breaking:**` bullet:

```
## Next

- **Breaking:** Requires Elixir 1.18.
- **Breaking:** Drop support for OTP 26.   ← new breaking entry, after the existing one
- Replace `httpoison` with `req` as the HTTP client.
```
