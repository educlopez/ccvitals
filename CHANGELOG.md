# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Read OAuth credentials from macOS Keychain for Claude Code 2.x+ (profile-specific service names with SHA256 hash)
- Fall back to `.credentials.json` for older Claude Code versions and non-macOS platforms
- Allow empty `subscriptionType` to proceed with API call instead of blocking (only skip explicit `api` type)

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
