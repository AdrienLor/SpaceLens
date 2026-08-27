# Legacy baseline — SpaceLens 1.1

This document freezes the expected behavior of the legacy application before the scanning-engine refactor.

## Reference revision

- Branch at refactor start: `main`
- Commit: `7ed498e792d8548163ae235176aa742c81f8bdde`
- Application version: `1.1`
- Minimum documented system: macOS 14

## Purpose

The scenarios below are characterization checks, not a statement that every legacy behavior is correct. Known defects must be recorded explicitly and corrected through reviewed changes rather than silently preserved.

## Reference scenarios

### 1. Select and open a readable folder

1. Launch SpaceLens.
2. Select a readable folder containing files and subfolders.
3. Confirm that the breadcrumb displays the selected path.
4. Confirm that entries appear progressively and are ordered by decreasing size.
5. Confirm that the global scanning indicator eventually stops.

Expected legacy behavior:

- Files display their size immediately.
- Direct child folders display a loading indicator until their size is computed.
- The first 100 entries are shown; additional entries can be loaded in batches of 100.

### 2. Navigate into a subfolder and back

1. Open a readable subfolder from the list.
2. Navigate to another subfolder.
3. Use the breadcrumb and reset controls.

Expected legacy behavior:

- The list is replaced with the selected folder contents.
- Previously completed folder results are reused from the in-memory cache.
- Reset returns to the folder selected through the folder picker.

Known defect:

- A folder opened by drag and drop is not stored as the root; Reset returns to the welcome screen.

### 3. Empty folder

1. Select or navigate to a readable empty folder.

Expected product behavior:

- The folder is identified as empty and remains navigable.
- It is not reported as access denied.

Known legacy defect:

- Empty child folders may be marked `accessDenied` and displayed as “Denied or Empty”.

### 4. Inaccessible or partially readable folder

1. Scan a directory containing at least one protected child.
2. Scan a directory whose root cannot be enumerated.

Expected product behavior:

- Empty, partially readable, and fully denied directories are represented as distinct states.
- Readable results remain available when only part of the hierarchy is denied.
- The application does not crash or become stuck in a scanning state.

Legacy behavior to characterize:

- A root that yields no entries is reported as “Denied or Empty” and the application returns to the previous valid view.

### 5. Hidden files

1. Scan a fixture containing a visible file and a dot-prefixed file of known sizes.
2. Compare the reported total with the fixture sizes.

Expected product behavior:

- Hidden files are included by default in disk-usage totals.
- A future user option may hide them visually without removing their size from aggregate totals.

Known legacy defect:

- The scanner uses `.skipsHiddenFiles`, so hidden content is absent from both the list and totals.

### 6. Package directories and symbolic links

1. Scan a fixture containing a macOS package such as an `.app` directory.
2. Scan a fixture containing a symbolic link.
3. Include a symbolic-link cycle in an isolated test fixture.

Expected product behavior:

- Package handling is explicit and consistent.
- Symbolic links never cause cycles or duplicate unbounded traversal.
- The chosen policy is documented in scan options.

Legacy behavior:

- Package descendants are skipped by the deep-size fallback.
- Symbolic-link semantics are not explicitly defined.

### 7. Size semantics

1. Scan fixtures containing a regular file, sparse file, and compressed or cloned file when supported.
2. Repeat the sunburst scan with depths 3 through 8.

Expected product behavior:

- One documented metric is used consistently: logical size or allocated size.
- Changing visualization depth does not change the root total.

Known legacy defect:

- Direct files use logical size while the depth-limit fallback uses allocated size, so totals may vary with sunburst depth.

### 8. Sunburst visualization

1. Switch from List to Sunburst.
2. Change depth from 3 through 8.
3. Hover sectors and navigate by clicking a folder sector.
4. Use Finder and Copy Path contextual actions.

Expected product behavior:

- The sunburst and list derive from the same scan result.
- Changing depth does not launch overlapping full-disk scans.
- Hovered sectors and contextual actions refer to the correct node.

Known legacy defect:

- Cancelling a scheduled refresh does not stop a hierarchy scan that has already started.

### 9. Cancellation and rapid navigation

1. Start a scan on a large directory.
2. Immediately navigate to a different directory.
3. Change sunburst depth repeatedly.
4. Return to the previous directory.

Expected product behavior:

- Obsolete work is cancelled promptly.
- An obsolete scan never updates the current view.
- Background work is bounded and the UI remains responsive.

Legacy behavior:

- List callbacks use a scan identifier to ignore stale results.
- Running sunburst work items do not observe cancellation.

### 10. Full Disk Access messaging

1. Launch without Full Disk Access.
2. Attempt to scan `/`.
3. Grant Full Disk Access, relaunch, and repeat.

Expected product behavior:

- The application explains the permission requirement without claiming that every protected path becomes readable.
- Empty directories are not used as evidence of denied access.

## Initial acceptance criteria for the refactor

The new scanning engine is ready for UI integration when:

- all fixture-based scanner tests pass;
- empty and denied folders are distinguishable;
- hidden-file behavior is explicit and tested;
- size semantics are consistent at every depth;
- symbolic-link traversal is bounded;
- cancellation prevents further result delivery;
- list and sunburst can consume the same immutable result tree;
- a scan never creates unbounded concurrent recursive jobs.

## Manual baseline record

Before replacing the legacy scanner, record for at least one small fixture and one representative large folder:

- total duration;
- time to first visible result;
- number of discovered entries;
- reported total size;
- peak memory when practical;
- time between cancellation request and end of disk activity.
