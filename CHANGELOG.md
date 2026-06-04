# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/educlopez/ccvitals/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/educlopez/ccvitals/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/educlopez/ccvitals/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/educlopez/ccvitals/compare/v1.3.0...v1.4.0
[1.0.0]: https://github.com/educlopez/ccvitals/releases/tag/v1.0.0
