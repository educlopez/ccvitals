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
> - **cost** — session cost in USD (e.g. $0.42)
> - **duration** — session wall-clock time (e.g. 1h23m)
> - **speed** — token throughput in tok/s
> - **vim** — vim mode indicator (N/I/V/VL)
> - **agent** — active agent name
> - **pr** — linked PR number and review state
> - **weekly** — 7-day quota bar with reset countdown
> - **pace** — burn-rate vs quota window (e.g. `pace +12%`)
> - **cache** — prompt-cache freshness countdown (e.g. `cache 4m12s`)
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

### 5. Ask which theme to use

Use AskUserQuestion to ask:

> Which color theme would you like?
> Current: [show current "theme" value from config, or "default" if absent]
>
> **1) default** — classic terminal 16-color palette (backward compatible)
> **2) pastel** — soft lavender/cyan palette
> **3) tokyo-night** — blue/purple night palette (Tokyo Night)
> **4) catppuccin** — soft pastel palette (Catppuccin Mocha)
> **5) dracula** — high-contrast dark palette (Dracula)
> **6) nord** — arctic, cool-toned palette (Nord)
> **7) mono** — bold/white only, no color (minimal setups)
> **8) custom** — specify your own hex colors
>
> Enter 1–8.

If they choose **8 (custom)**, use AskUserQuestion to ask for each of the 7 color keys (`red`, `green`, `blue`, `yellow`, `cyan`, `gray`, `magenta`) as hex values (`#RRGGBB`). Any key left blank keeps the default value.

Save the theme name as `CHOSEN_THEME` (e.g. `"tokyo-night"`). For custom, also save a `colors` object with the non-blank entries.

### 5b. Ask about context display mode (optional)

Use AskUserQuestion to ask:

> How would you like the context window displayed? (leave blank to keep current / use default)
>
> - **percent** (default) — `░░░░░░░░░░░░░░░ 13%`
> - **tokens** — `░░░░░░░░░░░░░░░ 26.0k/200k`
> - **both** — `░░░░░░░░░░░░░░░ 26.0k/200k 13%`
>
> Enter `percent`, `tokens`, or `both` (or press Enter to keep current).

Save as `CONTEXT_DISPLAY`. If the user presses Enter, keep the existing value (omit the key if not already set).

### 6. Write `~/.claude/.statusline-config.json`

Build the config JSON and write it to `$CONFIG_DIR/.statusline-config.json`. Preserve the existing `modules` and `modules_line2` keys; add or update the `theme` key (and optional `colors` key for custom). If `CONTEXT_DISPLAY` was chosen and is not `"percent"`, also set `"context_display"` in the config.

**Single-line layout** (no two-line selection or empty line2):

```json
{
  "modules": ["directory", "model", "context", "usage", "git"],
  "theme": "tokyo-night"
}
```

**Two-line layout** (modules on line 1 = chosen minus line2 set; line2 set in `modules_line2`):

```json
{
  "modules": ["directory", "model", "git"],
  "modules_line2": ["context", "usage", "lines", "mode"],
  "theme": "catppuccin"
}
```

**Custom colors** (only override specific keys; rest fall back to default):

```json
{
  "modules": ["directory", "model", "context", "usage", "git"],
  "theme": "custom",
  "colors": {
    "blue": "#7aa2f7",
    "green": "#9ece6a"
  }
}
```

The exact rule (matching install.sh behavior):
- `modules` = chosen modules MINUS the ones that go on line 2
- `modules_line2` = the line 2 subset (only included if non-empty)
- `theme` = chosen theme name string (omit or `"default"` for legacy colors)
- `colors` = only present when theme is `"custom"`

Build and write using Bash. Read the current config first and merge with jq to preserve all existing keys:

```bash
# Read current config (default to {} if missing)
current=$(cat "$CONFIG_DIR/.statusline-config.json" 2>/dev/null || echo '{}')

# For single-line with a named theme (adjust arrays and theme as needed):
echo "$current" | jq \
  --argjson mods '["directory","model","context","usage","git"]' \
  --arg theme 'tokyo-night' \
  '. + {"modules": $mods, "theme": $theme} | del(.modules_line2) | del(.colors)' \
  > "$CONFIG_DIR/.statusline-config.json"

# For two-line layout with theme:
echo "$current" | jq \
  --argjson mods '["directory","model","git"]' \
  --argjson l2 '["context","usage","lines","mode"]' \
  --arg theme 'catppuccin' \
  '. + {"modules": $mods, "modules_line2": $l2, "theme": $theme} | del(.colors)' \
  > "$CONFIG_DIR/.statusline-config.json"

# For custom colors (adjust colors object as needed):
echo "$current" | jq \
  --argjson mods '["directory","model","context","usage","git"]' \
  --argjson colors '{"blue":"#7aa2f7","green":"#9ece6a"}' \
  '. + {"modules": $mods, "theme": "custom", "colors": $colors} | del(.modules_line2)' \
  > "$CONFIG_DIR/.statusline-config.json"
```

### 7. Check the statusLine key in settings.json

Read `$CONFIG_DIR/settings.json`. If the `statusLine` key is missing (the user may have set up ccvitals via git clone + install.sh and the key is already there, or it was removed), ask the user:

> I notice `statusLine` is not set in settings.json. Would you like me to set it now? (y/n)
>
> This requires knowing the absolute path to statusline.sh. Run: `echo "$CLAUDE_PLUGIN_ROOT"` to find it, or enter the path manually.

Only update settings.json if the key is missing AND the user confirms. Do not overwrite an existing key.

### 8. Confirm success

Tell the user:

> ccvitals reconfigured!
>
> Line 1 modules: [list]
> Line 2 modules: [list, or "none (single-line layout)"]
> Theme: [chosen theme name]
>
> Changes take effect at next session start (restart Claude Code).
