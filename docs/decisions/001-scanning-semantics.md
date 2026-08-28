# ADR 001: Scanning semantics

- Status: Accepted
- Date: 2026-08-28

## Context

The legacy scanner mixes logical file size with allocated size, skips hidden files, treats an empty enumeration as access denied, and does not define package or symbolic-link behavior. These choices make totals dependent on scan depth and prevent reliable comparison with disk usage.

## Proposed decisions

1. Include hidden files in aggregate disk-usage totals by default.
2. Keep visual filtering separate from aggregation.
3. Represent folder readability explicitly as readable, partially readable, or denied.
4. Treat an empty readable folder as a successful result with size zero.
5. Never recursively follow symbolic links by default.
6. Treat macOS packages as directories for disk accounting, with an option to present them as single visual nodes.
7. Use one size metric consistently throughout a scan.
8. Make cancellation cooperative and prevent result delivery after cancellation.
9. Bound filesystem concurrency.

## Size metric

Allocated size is the primary metric because SpaceLens is a disk-space analyzer.
Logical size is collected alongside it for inspection and future presentation,
but changing visualization depth must never change either total.

## Consequences

The scanner API will require explicit options and richer result states. The list and sunburst will consume the same immutable result tree. Existing totals may change when hidden content and consistent size accounting are introduced.
