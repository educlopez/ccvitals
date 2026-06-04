# ccvitals

A real-time statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows usage quota, context window, git status, and more — right in your terminal.

![ccvitals screenshot](assets/screenshot.png)

## Install

Install ccvitals as a Claude Code plugin — no cloning or manual config required:

```
/plugin marketplace add educlopez/ccvitals
/plugin install ccvitals@ccvitals
/ccvitals:setup
```

`/ccvitals:setup` asks which modules you want, writes the config, and wires up `settings.json` automatically. Then restart Claude Code.

To reconfigure modules or switch to a two-line layout later:

```
/ccvitals:configure
```

### Manual install (alternative)

If you prefer a git-clone workflow (symlinked install, instant `git pull` updates):

```bash
git clone https://github.com/educlopez/ccvitals.git
cd ccvitals
./install.sh
```

The installer shows an interactive menu where you pick which modules to enable:

```
ccvitals — Choose your modules:

  [x] 1) Directory      my-project
  [x] 2) Model          Opus 4.6
  [x] 3) Context        ░░░░░░░░░░░░░░░ 12%
  [x] 4) Usage quota    Max ██████░░░░ 58% 3h42m
  [x] 5) Git status     (main | 3 files +42 -8)

  Toggle: enter number (e.g. 4). Accept: Enter. All: a
```

Then restart Claude Code.

#### Install options

```bash
# Force reinstall (relink script + overwrite settings.json statusLine key)
./install.sh --force

# Skip menu — install all modules
./install.sh --all

# Skip menu — pick specific modules
./install.sh --modules=model,context,usage

# Two-line layout (these modules drop to row 2)
./install.sh --all --line2=context,usage,rtk,mode,lines

# Combine flags
./install.sh --force --modules=context,usage,git
```

The interactive installer also asks, after you pick your modules, which of
them should drop to a second line (enter their numbers, or press Enter for a
single line).

#### Update

```bash
cd ccvitals && git pull
```

Because the script is symlinked, `git pull` updates the statusline instantly —
no reinstall needed. Restart Claude Code to see the new version.

#### Change modules later

Run `/ccvitals:configure` (plugin install) or re-run the installer with `--force`. You can also edit `~/.claude/.statusline-config.json` directly:

```json
{
  "modules": ["directory", "model", "context", "usage", "git", "rtk", "codegraph", "lines", "mode"]
}
```

Remove any module from the array to hide it.

### Two-line layout

Add an optional `modules_line2` array to render those modules on a **second row**. Modules stay in `modules` for line 1; anything in `modules_line2` drops to line 2. Omit `modules_line2` entirely for a single line.

```json
{
  "modules": ["directory", "model", "git", "codegraph"],
  "modules_line2": ["context", "usage", "rtk", "mode", "lines"]
}
```

Renders as:

```
my-project | Opus 4.6 | (main | 3 files +42 -8) | ⬡ 11.7k
███░░ 21% ⚠ | Max 58% 3h42m | rtk 86.8%↓ | ⚡ xhigh | +264 -195
```

## Modules

| Module | What it shows |
|--------|---------------|
| `directory` | Current project folder name |
| `model` | Active model (Opus 4.6, Sonnet 4.6, etc.) |
| `context` | Context window progress bar + percentage; turns red with a `⚠` when the context is large (≥150k tokens or over 200k) — a nudge to `/compact`, since long context is expensive even when cached |
| `usage` | 5h quota bar, reset timer, plan badge (Pro/Max/Team), 7d warning |
| `git` | Branch name, changed files count, lines added/removed |
| `rtk` | [RTK](https://github.com/) token-savings % — e.g. `rtk 86.8%↓` (needs the `rtk` CLI) |
| `codegraph` | CodeGraph index size + stale marker — e.g. `⬡ 11.7k ⚠3` (needs the `codegraph` CLI; only shows in indexed projects) |
| `lines` | Lines added/removed this session — e.g. `+264 -195` (cumulative agent edits, distinct from the git working-tree diff) |
| `mode` | Reasoning effort level + fast-mode flag — e.g. `⚡ xhigh` |

> `rtk`, `codegraph`, `lines`, and `mode` are **opt-in** (off by default).
> `rtk` and `codegraph` cache their output (rtk 60s globally, codegraph 15s per
> project) and refresh in the background, so they don't slow down rendering;
> each silently hides itself when its CLI isn't installed. `lines` and `mode`
> read straight from the data Claude Code passes in, at zero extra cost.

## Features

- **Modular** — pick only the sections you want
- **Context window** — progress bar + percentage of context used
- **Usage quota** — 5-hour utilization with color-coded bar (Pro/Max/Team)
- **Reset timer** — countdown to when your 5h quota resets
- **7-day warning** — shows weekly utilization when above 70%
- **Git status** — branch name, changed files count, lines added/removed
- **Plan badge** — shows your subscription tier (Pro, Max, Team)
- **Smart caching** — usage data cached for 60s, refreshed in background
- **Cross-platform** — works on macOS, Linux, and WSL

## Color coding

| Usage level | Color |
|-------------|-------|
| 0-49% | Cyan |
| 50-74% | Yellow |
| 75-89% | Magenta |
| 90%+ | Red |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` — JSON processor ([install](https://jqlang.github.io/jq/download/))
- `git` — to clone and update the repo
- `bash` 3.2+ (pre-installed on most systems)

> The statusline itself uses `curl` at runtime to fetch your usage quota, but
> the installer no longer downloads anything — it links the cloned `statusline.sh`.

## How it works

1. Claude Code pipes JSON context (model, workspace, context window) to the script via stdin
2. The script reads `~/.claude/.statusline-config.json` to know which modules are enabled
3. For the usage module: reads OAuth credentials to fetch quota data from the Anthropic API
   - **macOS (Claude Code 2.x+):** reads from the macOS Keychain using profile-specific service names
   - **Fallback:** reads from `~/.claude/.credentials.json` (older Claude Code versions or non-macOS)
4. Usage data is cached locally (`~/.claude/.usage-cache/usage.json`) for 60 seconds to avoid blocking the statusline
5. Git info is gathered from the current workspace directory
6. Only enabled modules are rendered into the final colorized line

## Multi-account setup

If you use `CLAUDE_CONFIG_DIR` to manage multiple accounts, the statusline respects it:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

The installer also respects `CLAUDE_CONFIG_DIR` — run it with the variable set to install for a specific account. Each account gets its own module config.

## Compatibility

| Platform | Status |
|----------|--------|
| macOS | Supported |
| Linux | Supported |
| WSL | Supported |
| Windows (via Git Bash) | Supported |

## Uninstall

From the cloned repo:

```bash
./uninstall.sh
```

This removes the statusline symlink, module config, the `statusLine` key from your settings, and the usage cache directory. (The cloned repo is left untouched — delete it manually if you no longer want it.)

## License

MIT

