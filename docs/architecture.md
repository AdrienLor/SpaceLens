# Architecture

SpaceLens is organized by responsibility while remaining a single macOS application target.

## Source layout

- `SpaceLens/App`: application entry point and app-level commands.
- `SpaceLens/Domain`: UI-independent data types and display policies.
- `SpaceLens/Scanning`: filesystem traversal and metadata collection.
- `SpaceLens/Features/Browser`: folder navigation, list presentation, and its view model.
- `SpaceLens/Features/Sunburst`: sunburst rendering and interaction.
- `SpaceLens/Shared`: small cross-feature utilities.
- `SpaceLens/Resources`: property lists and asset catalogs.
- `SpaceLensTests`: unit and characterization tests.

## Dependency direction

`App` composes features. Features may depend on `Domain` and scanner protocols. Scanning may depend on `Domain`, but it must not depend on SwiftUI views. Shared utilities must not become a catch-all domain layer.

## Refactor direction

`FileSystemDiskScanner` is the single filesystem traversal implementation. It
publishes a cancellable event stream consumed by `DiskViewModel`, which derives
both the folder list and the sunburst hierarchy from the same result tree.

The `Node` domain model is the scanner result and the shared input for list and
sunburst presentation. Scan lifecycle state remains owned by `DiskViewModel`
rather than being mixed into filesystem data.
