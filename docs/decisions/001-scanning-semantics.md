# ADR 001: Scanning semantics

- Status: Proposed
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

## Open decision: size metric

Choose one primary metric before implementing the new scanner:

- Logical size is portable and familiar but may not match space consumed.
- Allocated size better matches disk usage but requires clearly documented filesystem semantics.

A secondary metric may be collected later, but UI totals must identify which metric they display.

## Consequences

The scanner API will require explicit options and richer result states. The list and sunburst will consume the same immutable result tree. Existing totals may change when hidden content and consistent size accounting are introduced.
