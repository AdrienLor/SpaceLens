# Changelog

All notable changes to SpaceLens will be documented in this file.

The project follows the principles of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Started the repository and scanning-engine refactor.
- Reorganized application sources by responsibility.
- Routed the folder list and sunburst through one shared scan result tree.
- Removed repeated filesystem scans triggered by sunburst refreshes.
- Removed the superseded synchronous scanner and its duplicate traversal logic.
- Consolidated scan results and presentation data into one `Node` model.
- Reduced scanner metadata reads and batched progress delivery for faster traversal.
- Added a globally bounded worker queue for root-level subtree scanning.
- Display root directories immediately while their sizes are still being calculated.
- Distinguish complete folders from depth-limited and package-boundary nodes.
- Allow the browser and sunburst to inspect descendants inside macOS packages.

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
