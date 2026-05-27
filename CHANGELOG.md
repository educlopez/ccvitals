# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/educlopez/claude-statusline/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/educlopez/claude-statusline/releases/tag/v1.0.0
