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

The legacy scanner and view model remain operational while a cancellable scanner contract is introduced. The new scanner will be integrated only after fixture-based characterization tests cover the baseline scenarios in `docs/legacy-baseline.md`.
