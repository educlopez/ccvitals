---
description: "Reconfigure ccvitals modules and layout"
allowed-tools:
  - Bash
  - Read
  - Edit
  - AskUserQuestion
---

Reconfigure ccvitals module selection and optional two-line layout.

## Steps

### 1. Determine the Claude config directory

```bash
echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

Save the output as `CONFIG_DIR`.

### 2. Read the current config (if any)

```bash
cat "$CONFIG_DIR/.statusline-config.json" 2>/dev/null || echo "{}"
```

Show the user their current module list so they know what's active.

### 3. Ask which modules to enable

Use AskUserQuestion to ask:

> Which modules do you want to enable?
> Current: [show current modules]
>
> **Core modules** (default on):
> - **directory** — current project folder name
> - **model** — active model name
> - **context** — context window bar + percentage
> - **usage** — 5h quota bar, reset timer, plan badge
> - **git** — branch name, changed files, lines diff
>
> **Optional modules** (opt-in):
> - **rtk** — RTK token-savings % (needs `rtk` CLI)
> - **codegraph** — CodeGraph index size (needs `codegraph` CLI)
> - **lines** — cumulative lines added/removed this session
> - **mode** — reasoning effort level + fast-mode flag
>
> List all modules you want enabled, separated by spaces.
> Example: `directory model context usage git lines mode`

Save the response as the new module list.

### 4. Ask about two-line layout

Use AskUserQuestion to ask:

> Do you want a two-line layout? (y/n)
>
> Two-line example:
> ```
> my-project | Opus 4.6 | (main | 3 files +42 -8)
> ███░░ 21% | Max 58% 3h42m | rtk 86.8%↓ | ⚡ xhigh
> ```

If **yes**, use AskUserQuestion again to ask:

> Which of your chosen modules should go on line 2?
> Chosen modules: [list from step 3]
>
> Enter module names separated by spaces, or press Enter to put everything on line 1.

Save the response as the `modules_line2` list (must be a subset of the chosen modules).

### 5. Write `~/.claude/.statusline-config.json`

Build the config JSON and write it to `$CONFIG_DIR/.statusline-config.json`.

**Single-line layout** (no two-line selection or empty line2):

```json
{
  "modules": ["directory", "model", "context", "usage", "git"]
}
```

**Two-line layout** (modules on line 1 = chosen minus line2 set; line2 set in `modules_line2`):

```json
{
  "modules": ["directory", "model", "git"],
  "modules_line2": ["context", "usage", "lines", "mode"]
}
```

The exact rule (matching install.sh behavior):
- `modules` = chosen modules MINUS the ones that go on line 2
- `modules_line2` = the line 2 subset (only included if non-empty)

Build and write using Bash:

```bash
# For single-line (adjust array as needed):
jq -n --argjson mods '["directory","model","context","usage","git"]' \
  '{"modules": $mods}' > "$CONFIG_DIR/.statusline-config.json"

# For two-line layout (adjust arrays as needed):
jq -n \
  --argjson mods '["directory","model","git"]' \
  --argjson l2 '["context","usage","lines","mode"]' \
  '{"modules": $mods, "modules_line2": $l2}' > "$CONFIG_DIR/.statusline-config.json"
```

### 6. Check the statusLine key in settings.json

Read `$CONFIG_DIR/settings.json`. If the `statusLine` key is missing (the user may have set up ccvitals via git clone + install.sh and the key is already there, or it was removed), ask the user:

> I notice `statusLine` is not set in settings.json. Would you like me to set it now? (y/n)
>
> This requires knowing the absolute path to statusline.sh. Run: `echo "$CLAUDE_PLUGIN_ROOT"` to find it, or enter the path manually.

Only update settings.json if the key is missing AND the user confirms. Do not overwrite an existing key.

### 7. Confirm success

Tell the user:

> ccvitals reconfigured!
>
> Line 1 modules: [list]
> Line 2 modules: [list, or "none (single-line layout)"]
>
> Changes take effect at next session start (restart Claude Code).
