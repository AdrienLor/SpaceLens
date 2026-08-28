# Architecture

The browser consumes throttled scanner progress events to present item and byte
counts without increasing filesystem reporting frequency. User cancellation is
cooperative and preserves already listed top-level results in the current view.

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

The scanner prefetches one metadata set per item. Discovery event depth can be
limited independently from tree depth, allowing the browser to receive direct
children progressively without flooding the main actor with deep descendants.
Progress events are batched while the final update always contains complete
statistics.

Root children are distributed across a fixed worker pool. Each worker scans one
subtree sequentially, so concurrency is globally bounded without recursive task
fan-out. The default of two workers is based on the synthetic throughput
benchmark; callers can still override it through `ScanOptions`.

Before root subtrees are processed, directory metadata is emitted as a `listed`
event. The browser uses it to show every direct folder immediately and tracks
pending sizes separately from the immutable `Node` model.

`Node.childrenState` distinguishes a genuinely empty or complete folder from a
tree leaf caused by the visualization depth limit or package grouping. Opening
such a folder starts a new root scan, making its next levels available without
retaining an unbounded whole-disk tree.

The generic scanner keeps package grouping as its conservative default. The
SpaceLens browser explicitly requests package descendants so applications such
as Xcode can be opened and inspected while retaining allocated-size accounting.

Completed root scans use a five-entry least-recently-used cache. Navigating
through many folders therefore cannot retain an unbounded series of overlapping
deep trees; evicted folders are scanned again if revisited.
