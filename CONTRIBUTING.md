# Contributing to SpaceLens

## Development flow

- Keep `main` releasable.
- Create focused branches from the current refactor branch while the migration is in progress.
- Prefer small pull requests that preserve observable behavior unless the change explicitly fixes a documented defect.
- Add or update characterization tests before replacing legacy behavior.
- Record user-visible changes in `CHANGELOG.md`.

## Running tests

Run the headless Domain and Scanning test suite with:

```bash
./scripts/test.sh
```

This path is suitable for local automation and CI because it does not require
the Xcode test runner. The shared Xcode scheme remains the reference for the
full application build and integration tests.

## Commit style

Use short imperative commit subjects, for example:

- `docs: record scan-size semantics`
- `test: characterize empty folder scanning`
- `refactor: introduce cancellable scanner contract`
- `fix: distinguish empty and denied folders`

## Pull-request checklist

- [ ] The project builds from a clean checkout.
- [ ] Relevant tests pass.
- [ ] New behavior is documented.
- [ ] Cancellation and error states have been considered.
- [ ] No unrelated formatting or generated-user files are included.

## Refactor constraints

During the scanning-engine refactor:

- the list and sunburst must converge on one result tree;
- scanning concurrency must remain bounded;
- obsolete scans must not deliver results;
- size semantics must not depend on visualization depth;
- empty, partially readable, and denied folders must remain distinguishable.
