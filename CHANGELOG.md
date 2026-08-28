# Changelog

All notable changes to SpaceLens will be documented in this file.

The project follows the principles of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Started the repository and scanning-engine refactor.
- Reorganized application sources by responsibility.

## [1.1] - 2025-09-28

### Added

- Interactive sunburst visualization.
- Progressive folder scanning and in-memory caching.
- Heatmaps by size and file type.
- Breadcrumb navigation and Finder contextual actions.

### Known issues

- Hidden files are excluded from disk-usage totals.
- Empty folders can be reported as access denied.
- Size semantics differ between parts of the scanner.
- Running sunburst scans do not observe cancellation.
