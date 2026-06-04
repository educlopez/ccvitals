---
description: "Install the ccvitals statusline"
allowed-tools:
  - Bash
  - Read
  - Edit
  - AskUserQuestion
---

Install the ccvitals statusline into Claude Code.

## Steps

### 1. Resolve the plugin path

Run the following via Bash to get the absolute plugin directory. The `$CLAUDE_PLUGIN_ROOT` environment variable is set during plugin command execution but is NOT available when statusline.sh renders — so you must write the resolved absolute path into settings.json.

```bash
echo "$CLAUDE_PLUGIN_ROOT"
```

Save the output as `PLUGIN_PATH`. If the output is empty, abort and tell the user: "Could not resolve CLAUDE_PLUGIN_ROOT. Please reinstall the plugin."

### 2. Determine the Claude config directory

```bash
echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

Save the output as `CONFIG_DIR`. All config files go here.

### 3. Ask the user which module preset to use

Use AskUserQuestion to ask:

> Which module preset would you like?
>
> **1) Essential** (recommended) — directory, model, context, usage, git
> **2) Everything** — all 16 modules (adds: rtk, codegraph, lines, mode, cost, duration, speed, vim, agent, pr, weekly)
> **3) Custom** — start with Essential, then choose which extras to add
>
> Enter 1, 2, or 3.

If they choose **3 (Custom)**, use AskUserQuestion again to ask:

> Which optional modules do you want to add to the Essential set?
> (You can pick any combination)
>
> - **rtk** — RTK token-savings % (needs the `rtk` CLI)
> - **codegraph** — CodeGraph index size (needs the `codegraph` CLI)
> - **lines** — Lines added/removed this session
> - **mode** — Reasoning effort level
> - **cost** — Session cost in USD (e.g. $0.42)
> - **duration** — Session wall-clock time (e.g. 1h23m)
> - **speed** — Token throughput in tok/s
> - **vim** — Vim mode indicator (N/I/V/VL)
> - **agent** — Active agent name
> - **pr** — Linked PR number and review state
> - **weekly** — 7-day quota bar with reset countdown
>
> List the names separated by spaces, or press Enter to skip all.

### 4. Build the module list

Based on the preset:
- **Essential**: modules = `["directory", "model", "context", "usage", "git"]`
- **Everything**: modules = `["directory", "model", "context", "usage", "git", "rtk", "codegraph", "lines", "mode", "cost", "duration", "speed", "vim", "agent", "pr", "weekly"]`
- **Custom**: Essential set plus whatever extras the user selected

There is no `modules_line2` in the setup flow (single-line layout). Use `/ccvitals:configure` to set up a two-line layout later.

### 5. Ask which theme to use

Use AskUserQuestion to ask:

> Which color theme would you like?
>
> **1) default** — classic terminal 16-color palette (backward compatible)
> **2) tokyo-night** — blue/purple night palette (Tokyo Night)
> **3) catppuccin** — soft pastel palette (Catppuccin Mocha)
> **4) dracula** — high-contrast dark palette (Dracula)
> **5) nord** — arctic, cool-toned palette (Nord)
> **6) mono** — bold/white only, no color (minimal setups)
>
> Enter 1–6 (or press Enter for default).

Save the chosen theme name as `CHOSEN_THEME`. If the user presses Enter or enters 1, set `CHOSEN_THEME="default"`.

### 6. Write `~/.claude/.statusline-config.json`

Write the file at `$CONFIG_DIR/.statusline-config.json` using Bash. Include the `theme` key (omit it when `CHOSEN_THEME` is `"default"` to keep the config minimal):

```json
{
  "modules": ["directory", "model", "context", "usage", "git"],
  "theme": "tokyo-night"
}
```

Replace the module array with the chosen modules and the theme with `CHOSEN_THEME`. Example Bash write:

```bash
# With a named theme:
jq -n --argjson mods '["directory","model","context","usage","git"]' \
  --arg theme 'tokyo-night' \
  '{"modules": $mods, "theme": $theme}' > "$CONFIG_DIR/.statusline-config.json"

# Without a theme (default / user pressed Enter):
jq -n --argjson mods '["directory","model","context","usage","git"]' \
  '{"modules": $mods}' > "$CONFIG_DIR/.statusline-config.json"
```

### 7. Update `~/.claude/settings.json`

Set the `statusLine` key to:

```json
{"type": "command", "command": "bash <PLUGIN_PATH>/statusline.sh"}
```

Where `<PLUGIN_PATH>` is the resolved absolute path from Step 1.

If `settings.json` already exists:
- Read it first
- Check if `statusLine` is already set
- If already set, overwrite it (the user ran setup intentionally)
- Preserve all other keys using jq:

```bash
jq --argjson sl '{"type":"command","command":"bash /absolute/path/statusline.sh"}' \
  '.statusLine = $sl' "$CONFIG_DIR/settings.json" > "$CONFIG_DIR/settings.json.tmp" \
  && mv "$CONFIG_DIR/settings.json.tmp" "$CONFIG_DIR/settings.json"
```

If `settings.json` does not exist, create it:

```bash
jq -n --argjson sl '{"type":"command","command":"bash /absolute/path/statusline.sh"}' \
  '{statusLine: $sl}' > "$CONFIG_DIR/settings.json"
```

### 8. Confirm success

Tell the user:

> ccvitals is installed! Enabled modules: [list chosen modules]
> Theme: [chosen theme name]
>
> The statusline will appear at the next session start (restart Claude Code or open a new session).
>
> To reconfigure modules, theme, or set up a two-line layout later, run `/ccvitals:configure`.
