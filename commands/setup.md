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
> **2) Everything** — all 9 modules (adds: rtk, codegraph, lines, mode)
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
>
> List the names separated by spaces, or press Enter to skip all.

### 4. Build the module list

Based on the preset:
- **Essential**: modules = `["directory", "model", "context", "usage", "git"]`
- **Everything**: modules = `["directory", "model", "context", "usage", "git", "rtk", "codegraph", "lines", "mode"]`
- **Custom**: Essential set plus whatever extras the user selected

There is no `modules_line2` in the setup flow (single-line layout). Use `/ccvitals:configure` to set up a two-line layout later.

### 5. Write `~/.claude/.statusline-config.json`

Write the file at `$CONFIG_DIR/.statusline-config.json` using Bash with the following JSON shape (this matches exactly what install.sh writes):

```json
{
  "modules": ["directory", "model", "context", "usage", "git"]
}
```

Replace the array contents with the chosen modules. Example Bash write:

```bash
jq -n --argjson mods '["directory","model","context","usage","git"]' \
  '{"modules": $mods}' > "$CONFIG_DIR/.statusline-config.json"
```

### 6. Update `~/.claude/settings.json`

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

### 7. Confirm success

Tell the user:

> ccvitals is installed! Enabled modules: [list chosen modules]
>
> The statusline will appear at the next session start (restart Claude Code or open a new session).
>
> To reconfigure modules or set up a two-line layout later, run `/ccvitals:configure`.
