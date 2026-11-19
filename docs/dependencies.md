# Dependencies, their age and licences

Every Swift dependency is pinned **exactly** (`exact:`), the resolved state is committed (`Package.resolved` in
`Packages/AppCore`, in `Tools/Generator`, and in the Xcode project), and every release is at least **two weeks old**
at the reference date below. A test (`tests/test_dependencies.py`) compares this table with the manifests and the
resolved files, so a change shows up in review. No dependency has a build-tool plugin that runs during a normal
build: the generator is run by hand (`ios/scripts/generate-client.sh`) and its output is committed.

Reference date: **2026-11-18**. Cutoff (14 days): 2026-11-04.

## What the app links

| Package | Version | Released | Licence | Why |
|---|---|---|---|---|
| swift-openapi-runtime | 1.13.4 | 2026-11-03 | Apache-2.0 | the runtime the generated client needs |
| swift-openapi-urlsession | 1.4.0 | 2026-10-22 | Apache-2.0 | the URLSession transport |
| swift-http-types | 1.8.0 | 2026-09-07 | Apache-2.0 | HTTP types; used directly by the bearer middleware |
| swift-collections | 1.7.5 | 2026-10-27 | Apache-2.0 | brought in by the URLSession transport; **pinned older than the newest** (1.7.6, 2026-11-10, was under two weeks old) |

## What generates the client (a developer tool, never part of the app)

| Package | Version | Released | Licence |
|---|---|---|---|
| swift-openapi-generator | 1.14.3 | 2026-10-26 | Apache-2.0 |
| OpenAPIKit | 6.4.0 | 2026-09-14 | MIT |
| swift-argument-parser | 1.8.2 | 2026-06-04 | Apache-2.0 |
| Yams | 6.2.2 | 2026-05-26 | MIT |
| swift-algorithms | 1.2.1 | 2025-02-10 | Apache-2.0 |
| swift-numerics | 1.1.1 | 2025-09-25 | Apache-2.0 |

`swift-openapi-generator` 1.14.4 (2026-11-05) was newer than the cutoff, so 1.14.3 is used.

## Raising a version

1. Pick the newest **stable** release published on or before (today − 14 days); read its release notes.
2. Change the `exact:` pin, run `swift package resolve` (in `Packages/AppCore` and, for the generator, `Tools/Generator`),
   commit `Package.resolved`, and update the table above with the release date and licence.
3. Run `ios/scripts/generate-client.sh` if the generator moved, and commit the regenerated client with it.
4. Check what the new version pulled in (`Package.resolved`) against the same two-week rule.
