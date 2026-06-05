# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.12.0] - 2026-06-05

### Added

- **`module_order` config key** — optional JSON array of module names controlling the left-to-right display order of segments (e.g. `["cost","git","context","model","directory"]`). Enabled modules not listed are appended after the listed ones in the default order. Unknown names are silently ignored (forward-compatible). When absent, behavior is byte-identical to previous versions. Works with powerline mode and `modules_line2` routing (order is independent of line assignment). Config values are validated against the known module list — never evaluated or executed. `module_order` added to per-project config supported-keys list.
- 7 new tests in `test/statusline.bats` covering: default order unchanged when key absent, custom order respected, unknown names ignored, unlisted enabled modules appended, per-project config override, powerline + module_order, and modules_line2 routing preserved with custom order.
- **Hooks-as-state-writers infrastructure** — `ccvitals-hook.sh`: a new script registered in Claude Code's `hooks` config that writes per-session state to `~/.claude/.ccvitals-state/<session_id>.json` on every event (`SessionStart`, `MessageDisplay`, `TaskCreated`, `PostCompact`, `Stop`). Tracks `last_event`, `last_event_at`, `session_title`, `message_count`, and `tasks_created`. Atomic writes (tmp + mv). Stale files (>48h) cleaned up on `SessionStart`. Always exits 0, never writes stdout — safe to run on every message. Pure bash 3.2 + jq.
- **`session` module** (`mod_session`, default off) — shows session title written by the hook script (e.g. `§ my-refactor`); hidden when hooks not installed, state file absent, or no title set. With `"session_turns": true` config key also shows turn counter from `message_count` (e.g. `§ my-refactor ·12`). Single state-file read shared between title and turns.
- **`--hooks` flag for `install.sh`** — registers `ccvitals-hook.sh` in `~/.claude/settings.json` under `hooks` for all five events. Merges into existing hook arrays without clobbering user-defined hooks; idempotent (no duplicate entries on re-run). Interactive installer asks whether to wire hooks after the module menu. Backs up `settings.json` before modifying. `TOTAL_STEPS` adjusted accordingly.
- **`uninstall.sh` hooks cleanup** — removes only the ccvitals-specific hook entries (matched by `ccvitals-hook.sh` path) from all event arrays in `settings.json`; empties arrays are pruned; user hooks are preserved. Also removes the `~/.claude/.ccvitals-state/` directory.
- **`session_turns` config key** — when `true`, the `session` module appends `·N` turn counter to the title; default `false`.
- `session` added to `_KNOWN_MODULES`, `_DEFAULT_MODULE_ORDER`, responsive-width drop order, and smart-visibility section in `statusline.sh`; module count updated to 29; `install.sh` interactive menu extended to 29 entries.
- 38 new tests in `test/hooks.bats` covering: hook exits/no-stdout on all five events, malformed JSON, empty stdin, state file creation and fields, `message_count` and `tasks_created` counter increments, `session_title` capture from both `session.title` and `hookSpecificOutput.sessionTitle`, title preservation across events, atomic write (valid JSON + no stray tmp files), session_id sanitisation; session module with/without state file, title display, `session_turns` sub-option, zero-turns suppression, malformed state file graceful; `install --hooks` wires all events, merges without clobbering, idempotent; `uninstall` removes only ccvitals entries and preserves user hooks, removes state dir.

## [1.11.0] - 2026-06-05

### Added

- **Skill names in `tools` module** — when a `Skill` tool invocation is in flight, the `tools` module now shows the skill's name from `.input.skill` (e.g. `⚒ deploy-to-vercel`) in YELLOW instead of the generic `Skill` label. Falls back to `Skill` when `.input.skill` is absent. Controlled by the `tools_skill_names` config key (default: `true`; set to `false` to restore the previous generic label in CYAN).
- **MCP tool name compaction in `tools` module** — `mcp__server__tool` names are compacted to `server:tool` format (e.g. `mcp__codegraph__codegraph_search` → `codegraph:codegraph_search`), keeping the statusline readable even with many MCP tools installed.
- **`workflows` module** (`mod_workflows`, default off) — detects running `Workflow` tool-use entries in the transcript (tool_use named `"Workflow"` with no matching `tool_result` yet) and shows `⟳ N wf` (e.g. `⟳ 1 wf`); hidden when none pending. Integrates into the existing single `tail -n 300` + one `jq` pass shared by `tools`/`agents`/`todos` — zero additional transcript reads. `Workflow` entries are excluded from the `tools` module count.
- `ICON_WORKFLOWS` (`⟳`) added to all three icon sets (`unicode`, `ascii` → `wf:`, `nerd`); `workflows` added to responsive-mode drop order (between `todos` and `git`)
- `workflows` added to `--all` module list, `KNOWN_MODULES`, interactive menu, and `--help` in `install.sh`; module count updated from 27 to 28
- 11 new tests in `test/statusline.bats` covering: Skill name display, Skill fallback, YELLOW color for Skill, `tools_skill_names=false` disables name, MCP compaction, workflow count display, workflow hidden when completed, multiple workflows count, workflow hidden without transcript, workflow hidden with no Workflow tool, Workflow excluded from tools module

- **`thinking` module** (`mod_thinking`, default off) — displays reasoning effort level with a `✦` icon (e.g. `✦ xhigh`); reads `.effort.level` from stdin with `.thinking_effort` as a fallback field; color: CYAN for `xhigh`/`xlarge`, MAGENTA for `high`/`large`, GRAY otherwise; hidden when field absent; smart-mode suppresses `low`/`medium`
- **`mcp` module** (`mod_mcp`, default off) — shows configured MCP server count (e.g. `⬡ 4`); aggregates servers from `.mcp.json` in the workspace root (flat `{name:…}` and `{mcpServers:{…}}` formats), `~/.claude.json`, and `~/.claude/settings.json`; hidden when count is zero; mtime-based file cache keeps every render at constant cost (count-only — no `claude mcp list` call on the render path)
- **`git_operation`** config key (default `false`) — prepends a RED operation banner when `.git/MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`, `CHERRY_PICK_HEAD`, or `BISECT_LOG` are present (e.g. `MERGE (main …)`)
- **`git_status_split`** config key (default `false`) — replaces the `N files` aggregate with staged/unstaged/untracked counts (e.g. `+2 ~3 ?1`); reuses the existing `git status --porcelain` pass, no extra subprocess
- **`git_sha`** config key (default `false`) — appends short commit SHA (GRAY) to the git segment
- **`git_stash`** config key (default `false`) — appends stash count as `≡N` (GRAY) when stash is non-empty; hidden when empty
- **`git_age`** config key (default `false`) — appends time since last commit in compact format: `5m`, `2h`, `3d`, `4w` (GRAY)
- `ICON_THINKING` (`✦`) and `ICON_MCP` (`⬡`) added to all three icon sets (`unicode`, `ascii`, `nerd`)
- `thinking` and `mcp` added to responsive-mode drop order (dropped before `codegraph`)
- `thinking` and `mcp` added to smart-visibility suppression logic; `git_operation`/`git_status_split`/`git_sha`/`git_stash`/`git_age` keys documented in per-project config supported-keys list
- install.sh: `thinking` and `mcp` added to `--all` module list and `KNOWN_MODULES`; count updated from 24 to 26
- **Session budget cap** (`session_budget`, number, USD) — new config key for the `cost` module. When set, displays `$1.50/$5.00` (current / cap) with color: GRAY <50%, YELLOW 50–79%, RED ≥80%. When unset, the module behaves exactly as before. Supports per-project override via `.ccvitals.json`.
- **`spend` module** (`mod_spend`, default off) — 7-day and 30-day historical spend aggregated from the per-day ledger that the `daily` module writes to `~/.claude/.ccvitals-daily/YYYY-MM-DD.json`. Displays `7d $12.40 · 30d $48` (compact, same money format as other modules). Config key `spend_windows` (array, default `["7d","30d"]`) selects which windows appear. Accumulation starts from when `daily` was first enabled; no backfill of pre-install transcripts. Reads only today-relative day-files from disk with a pure-awk date-diff (no external calls); hidden when ledger dir absent.
- `spend` added to `--all` module list and `KNOWN_MODULES` in `install.sh`; responsive drop order updated to include `spend` (between `daily` and `tokens`); `session_budget` and `spend_windows` added to per-project config supported-keys lists
- `test/cost_guardrails.bats`: 19 new tests covering session budget (no-budget baseline, denominator display, color thresholds at 50%/80%, zero budget, per-project override) and spend module (hidden by default, missing dir, populated ledger, multi-window, separator dot, `spend_windows` config, zero spend, malformed file, crash guard)

## [1.10.1] - 2026-06-05

### Fixed

- Subagent rows: when Claude Code feeds the same text into both `label` and `description` (common — the Agent `description` parameter populates both), the row printed it twice; the description is now omitted when it duplicates the display name

## [1.10.0] - 2026-06-04

### Added

- **Homebrew tap** — `brew install educlopez/tap/ccvitals`; the `ccvitals` wrapper runs the bundled installer (`ccvitals --all`, `ccvitals uninstall`)
- **Per-project config** (`.ccvitals.json`) — place a `.ccvitals.json` at any workspace root to deep-override the global config for that project. Any key present in the project file wins; absent keys keep their global values. Merge is done with `jq -s '.[0] * .[1]'` into a single `effective_config` variable; all config reads now use that variable (refactor eliminates all scattered `jq ... "$statusline_config"` calls). Values are only consumed as JSON data, never executed.
- **Smart visibility** (`"smart": true`, default `false`) — modules only appear when their value is notable: `cost` when ≥ $1.00; `cache` when remaining < 60s or cold; `pace` (delta mode) when delta < 0; `context` when ≥ 50%; `duration` when ≥ 1h. All other modules unaffected. `false` behavior is byte-identical to before.
- **Icon set** (`"icons"`: `"unicode"` / `"ascii"` / `"nerd"`) — all icon glyphs are resolved into variables at startup. `unicode` (default) is byte-identical to the previous behavior. `ascii` replaces unicode glyphs with plain-ASCII equivalents (⚒→T:, ◉→A:, ☑→[x], ⌛→eta, ⇅→io, ↯→cmp, ⚡→!, ⚠→(!), █░→#-). `nerd` uses Nerd Font icons.
- **Responsive width** (`"responsive": true`, default `false`) — when `COLUMNS` is set and numeric, ccvitals drops lowest-priority modules from line 1 until the visible length fits. Priority: codegraph, rtk, lines, duration, cost, speed, vim, weekly, daily, tokens, compactions, pr, agent, mode, cache, pace, tools, agents, todos, git, usage, context, model, directory. Only applies to line 1 in non-powerline mode; powerline + responsive is silently skipped.
- `test/statusline.bats`: 17 new tests covering per-project override, merge semantics, invalid project JSON, smart hide/show for cost/context, icons ascii rendering, responsive no-crash, and COLUMNS-generous survival

### Fixed

- Smart visibility: the cache-hide pattern matched the "2m" inside ANSI color codes (e.g. `\033[0;32m`), blanking the cache module unconditionally — now matches on ANSI-stripped text
- Responsive width: visible length now counts characters (`wc -m`) instead of bytes — multi-byte bar glyphs (`█`) were over-counted 3×, dropping modules far too aggressively
- A project-only `.ccvitals.json` now works even when no global config exists
- Invalid JSON in the global config prints a one-line stderr warning instead of silently disabling all configuration
- `usage` reset timestamp: ISO date strings (which also start with a digit) were matched by the epoch branch and fed into integer arithmetic, printing a `value too great for base` error to stderr — the case now matches on any-non-digit first
- Responsive recompose uses bash indirect expansion (`${!var}`) instead of `eval`

## [1.9.0] - 2026-06-04

### Added

- **Subagent rows** (`subagent-statusline.sh`) — per-sub-agent row renderer for the Claude Code agent panel. Replaces the default `name · description · tokens` row with a theme-aware line: status icon (`◐` CYAN running / `✓` GREEN completed / `✗` RED stopped / `·` GRAY unknown), label/name, description truncated to fit terminal width, k/M token count, and cwd basename. Reads `columns` and `tasks[]` from the `subagentStatusLine` stdin contract; emits one compact JSON line per task. Handles unknown statuses and all edge cases (empty tasks, malformed stdin) gracefully with zero output and exit 0. Theme-aware: reads `~/.claude/.statusline-config.json` and applies the same color presets as the main statusline.
- `install.sh`: symlinks `subagent-statusline.sh` into the config dir and writes the `subagentStatusLine` key to `settings.json` alongside `statusLine` (both `--force` and fresh installs)
- `uninstall.sh`: removes the `subagent-statusline.sh` symlink and deletes the `subagentStatusLine` key from `settings.json`
- `commands/setup.md`: Step 7 now writes both `statusLine` and `subagentStatusLine` keys
- `README.md`: new "Subagent rows" section (after Powerline) describing the row format and how to disable
- `test/subagent.bats`: 19 new tests covering JSON contract, icon/color per status, description truncation, k/M token formatting, label-over-name preference, cwd basename, theme presets, and all edge cases

- **Quota forecast** — `pace` module gains a new `pace_display: "eta"` config key. ETA mode computes the burn rate from elapsed time and used percentage, then projects when the 5h quota will exhaust. If exhaustion is before the reset: `⌛ ~17:40` (RED if within 1h, YELLOW otherwise). If quota will outlast the reset: `⌛ ok` (GREEN). The existing `"delta"` mode is the default and unchanged.
- **Daily budget module** (`daily`, opt-in) — cross-session spend for the current day. Stores per-session costs in `~/.claude/.ccvitals-daily/YYYY-MM-DD.json`, sums all sessions, and displays `Σ $4.20`. Optional `daily_budget` config key (number, USD) adds a budget denominator and colors: GREEN <50%, YELLOW <80%, MAGENTA <100%, RED ≥100%. Day-files older than 7 days are pruned automatically. Hidden when no session_id or no cost in stdin.
- **Weekly per-model split** — `weekly` module gains `weekly_split: true` config key. When the OAuth usage cache has `seven_day_opus`/`seven_day_sonnet` utilization, renders `7d O:42% S:18%` (colored per standard thresholds) instead of the single progress bar. Falls back to the bar when per-model keys are absent or the cache is missing.
- **Compactions module** (`compactions`, opt-in) — counts `{"type":"system","subtype":"compact_boundary"}` entries in the transcript using a fast `grep -c` on the full file. Displays `↯ 2` (GRAY). Hidden when count is 0 or transcript is absent.
- **Session tokens module** (`tokens`, opt-in) — cumulative session input/output token counts using an incremental cache keyed by session_id (`~/.claude/.ccvitals-tokens/<id>.txt`). On each render only new transcript lines are processed; totals accumulate. Displays `⇅ 1.2M/45k` (in/out, k/M formatted). Resets on transcript shrink (compact). Hidden when transcript is absent.
- `install.sh`: menu extended to 24 entries (22=daily, 23=compactions, 24=tokens); `--all` now includes all 24 modules; `KNOWN_MODULES` updated
- `commands/setup.md` and `commands/configure.md`: new modules added to optional lists; `pace_display`, `daily_budget`, `weekly_split` documented

## [1.8.1] - 2026-06-04

### Fixed

- **OSC 8 hyperlinks leaked literal escape text** — the ST terminator (`\033\\`) written inside double quotes collapsed its backslashes at assignment time, so `echo -e` paired the orphan backslash with the next color code's backslash and rendered visible `033[0;33m` garbage after the branch/PR link. All OSC 8 sequences now use the BEL terminator (`\007`), which avoids the backslash ambiguity entirely and is equally supported by terminals
- Regression test: visible output (real ESC bytes stripped) must never contain literal `033[` text; OSC 8 must be BEL-framed

## [1.8.0] - 2026-06-04

### Added

- **Powerline mode** — set `"powerline": true` in `.statusline-config.json` to render each module as a background-shaded segment separated by the Nerd Font U+E0B0 (``) glyph; segments alternate between two per-theme background shades; a final trailing arrow resets to the terminal default background
- Per-theme powerline background pairs: truecolor (`48;2;R;G;B`) for pastel, tokyo-night, catppuccin, dracula, and nord; 256-color fallback (`48;5;236`/`48;5;238`) for mono and default
- `"powerline_separator"` config key to override the glyph with any string (ASCII fallback for terminals without a Nerd Font)
- Internal `\033[0m` resets inside segments are automatically followed by the segment's background code so colors persist throughout each segment
- Two-line layout: each line restarts the alternating segment index and gets its own trailing separator
- No behavior change when `"powerline"` is absent or `false` — output is byte-identical to the previous render path
- `commands/configure.md`: new step 5c asking about powerline mode with Nerd Font note and custom separator prompt
- `README.md`: new "Powerline mode" section after Themes with config example, Nerd Font requirement, and custom separator usage

## [1.7.0] - 2026-06-04

### Added

- **Tools module** (`tools`, opt-in) — shows tool_use entries currently in flight (no matching tool_result yet): `⚒ Bash` (one pending) or `⚒ Bash +2` (first tool + overflow count); Task tool excluded (covered by `agents`); hidden when none pending
- **Agents module** (`agents`, opt-in) — shows Task tool_use entries without a matching result: `◉ code-reviewer` (one, using subagent_type or first 20 chars of description) or `◉ 3 agents` (multiple); hidden when none active
- **Todos module** (`todos`, opt-in) — shows progress from the last TodoWrite in the transcript window: `☑ 3/7`; GREEN when all completed, CYAN otherwise; hidden when no TodoWrite found or todos array empty
- All three transcript modules share one `tail -n 300` + one `jq` invocation per render; gated as a block when all three are disabled; transcript absent/missing → all hidden; malformed trailing lines handled gracefully (jq nonzero exit → all hidden)
- `install.sh` menu extended to 21 entries (19=tools, 20=agents, 21=todos); `--all` now includes all 21 modules; `KNOWN_MODULES` validation updated
- `commands/setup.md` and `commands/configure.md`: tools/agents/todos added to optional module lists; Everything preset updated to 21 modules

## [1.6.0] - 2026-06-04

### Added

- **Pastel theme** (`pastel`) — soft lavender/cyan palette
- Per-theme static preview images in the README (`assets/themes/*.png`), regenerable with `assets/generate-theme-previews.sh`
- **Git ahead/behind** — after the branch name, appends `↑N ↓M` when upstream diverges (GREEN ahead, YELLOW behind); both omitted when 0
- **OSC 8 clickable branch** — `git` module wraps the branch name in a terminal hyperlink (`ESC]8;;URL\ESC\\`) for GitHub/GitLab remotes; handles both `git@host:owner/repo.git` and `https://host/owner/repo.git` forms
- **OSC 8 clickable PR** — `pr` module wraps `PR #N` in an OSC 8 hyperlink when `pr.url` is present in stdin
- **Pace module** (`pace`, opt-in) — burn-rate vs 5h quota window: computes how far ahead/behind the expected consumption rate you are; GREEN ≥0%, YELLOW -10%–0%, RED <-10%; hidden when `rate_limits.five_hour` absent or window invalid
- **Cache module** (`cache`, opt-in) — Anthropic prompt-cache TTL countdown (300s from last transcript entry): `cache 4m12s` (GREEN/YELLOW/RED by urgency) or `cache cold`; reads `transcript_path` from stdin, hidden when absent
- **Context display modes** — new optional config key `context_display`: `"percent"` (default), `"tokens"` (e.g. `45.2k/200k`), or `"both"` (e.g. `45.2k/200k 23%`)

## [1.5.0] - 2026-06-04

### Added

- **Theming system** — set `"theme"` in `~/.claude/.statusline-config.json` to switch color presets without touching any code
- **Built-in presets**: `default` (legacy 16-color ANSI, backward compatible), `tokyo-night`, `catppuccin`, `dracula`, `nord`, `mono` (bold/white, no color)
- **Custom colors** — set `"theme": "custom"` with a `"colors"` object containing any of the 7 color keys (`red`, `green`, `blue`, `yellow`, `cyan`, `gray`, `magenta`) as `#RRGGBB` hex strings; missing keys fall back to defaults
- **Truecolor support** — preset/custom colors use `\033[38;2;R;G;Bm` SGR sequences; `default` and `mono` continue to use the classic 16-color codes
- **`hex_to_ansi` helper** — bash-3.2-compatible hex-to-truecolor conversion (no associative arrays)
- Theme selection added to `/ccvitals:setup` (step 5) and `/ccvitals:configure` (step 5)
- Theme showcase scene in the demo GIF (`assets/demo.tape` + `assets/demo.sh`)

### Fixed

- The `usage` module now renders directly from stdin `rate_limits` without requiring a successful OAuth fetch first — previously the stdin preference only applied after a cache file existed, so the module stayed empty when API credentials were unavailable or the API was rate-limiting
- The plan badge is omitted (instead of rendering an empty gray gap) when the subscription type is unknown

## [1.4.0] - 2026-06-04

### Added

- **Project renamed to ccvitals** — GitHub repo moved to `educlopez/ccvitals` (old URLs redirect)
- **Claude Code plugin distribution** — install via `/plugin marketplace add educlopez/ccvitals` + `/plugin install ccvitals@ccvitals`, then `/ccvitals:setup`; reconfigure anytime with `/ccvitals:configure`
- **Cost module** (`cost`) — session cost in USD, e.g. `$0.42`
- **Duration module** (`duration`) — session wall-clock time, e.g. `1h31m`
- **Speed module** (`speed`) — token throughput between renders, e.g. `150 tok/s`
- **Vim module** (`vim`) — vim mode indicator (`N`/`I`/`V`/`VL`), hidden when vim mode is off
- **Agent module** (`agent`) — active agent name, e.g. `@ security-reviewer`
- **PR module** (`pr`) — linked pull request number and review state, e.g. `PR #123 approved`
- **Weekly quota module** (`weekly`) — 7-day usage bar with reset countdown, e.g. `7d: ███░░░░░░░ 38%`

### Changed

- The `usage` module now prefers `rate_limits` data from Claude Code's stdin JSON (zero-latency, no network) and only falls back to the OAuth API when absent

## [1.3.0] - 2026-05-27

### Added

- Installer support for the two-line layout: a `--line2=LIST` flag places those modules on row 2 (the rest stay on row 1), and the interactive installer now asks which selected modules should drop to a second line

## [1.2.0] - 2026-05-27

### Added

- **Session lines module** (`lines`) — lines added/removed this session, e.g. `+264 -195`, read from Claude Code's `cost` data
- **Mode badge module** (`mode`) — reasoning effort level + fast-mode flag, e.g. `⚡ xhigh`
- Context-pressure alert: the `context` module turns red with a `⚠` when the context is large (≥150k tokens or `exceeds_200k_tokens`), nudging `/compact`
- Optional two-line layout via a `modules_line2` config array — modules listed there render on a second row (omit it for a single line)

## [1.1.0] - 2026-05-27

### Added

- **RTK module** — global token-savings percentage from `rtk gain` (e.g. `rtk 86.8%↓`); opt-in, hides itself when the `rtk` CLI is absent
- **CodeGraph module** — per-project index size with a stale marker from `codegraph status` (e.g. `⬡ 11.7k ⚠3`); opt-in, only shown in indexed projects
- Background-cached command helper so tool modules never block rendering (rtk cached 60s, codegraph 15s per project)

### Changed

- Installer reworked from `curl | bash` (copy) to `git clone` + symlink: `statusline.sh` is symlinked into the Claude config dir, so `git pull` updates the statusline instantly and multiple machines stay in sync through the repo
- `--all` now selects all seven modules (adds `rtk` and `codegraph`)
- Uninstaller removes the symlink, including dangling links

### Fixed

- Parse the quota reset timestamp as UTC on macOS — `date -j -f` was treating the trailing `Z` as local time, making the reset countdown short by the local UTC offset
- Read OAuth credentials from macOS Keychain for Claude Code 2.x+ (profile-specific service names with SHA256 hash)
- Fall back to `.credentials.json` for older Claude Code versions and non-macOS platforms
- Allow empty `subscriptionType` to proceed with API call instead of blocking (only skip explicit `api` type)

### Removed

- Installer `--update` mode (superseded by `git pull`)

## [1.0.0] - 2026-03-04

### Added

- Real-time statusline for Claude Code with modular design
- **Directory module** — shows current working directory name
- **Model module** — displays active Claude model (e.g., Opus 4.6)
- **Context module** — visual progress bar of context window utilization
- **Usage module** — OAuth-based quota tracking with 5-hour and 7-day windows, color-coded usage bars, and reset timer
- **Git module** — branch name, changed file count, and line diff stats
- Interactive module selector during installation (toggle modules on/off)
- Non-interactive installation via `--force`, `--all`, and `--modules=` flags
- Background usage cache with configurable TTL to avoid blocking the statusline
- Uninstaller script to cleanly remove all statusline components
- Cross-platform support for macOS and Linux (BSD and GNU date handling)
- Automatic `settings.json` configuration with backup on overwrite
- Per-user module configuration stored in `.statusline-config.json`

[1.12.0]: https://github.com/educlopez/ccvitals/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/educlopez/ccvitals/compare/v1.10.1...v1.11.0
[1.10.1]: https://github.com/educlopez/ccvitals/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/educlopez/ccvitals/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/educlopez/ccvitals/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/educlopez/ccvitals/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/educlopez/ccvitals/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/educlopez/ccvitals/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/educlopez/ccvitals/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/educlopez/ccvitals/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/educlopez/ccvitals/compare/v1.3.0...v1.4.0
[1.0.0]: https://github.com/educlopez/ccvitals/releases/tag/v1.0.0
