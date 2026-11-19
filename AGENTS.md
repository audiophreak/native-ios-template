# Project rules

This repository is the **native iOS Copier template** (`copier.yml` + `template/`), versioned by git tags. It is an
add-on to `web-core-template`: it renders only `ios/` and its own answers file (`.copier-answers.ios.yml`) into the
directory of a project that the web template generated with `auth` and `native_client`. It is not a generated
application, and it never contains or rewrites a web file.

## Commands

- `uv sync` — create the project-local environment from `uv.lock`
- `uv run pytest -m "not xcode"` — fast tests (rendering, layering, static rules, pins)
- `uv run pytest` — everything, including the generated client, `swift test` and `xcodebuild` for the simulator
  (needs Xcode 26 and an iOS Simulator runtime)
- `uv run python tools/gen_pbxproj.py [--check]` — the Xcode project is generated once by this tool and committed

## Working agreement

- Plan first for anything beyond a trivial fix; wait for approval on breaking changes.
- Keep changes small. Do not add, upgrade or remove dependencies without approval; pin exact versions (`pyproject.toml`,
  `uv.lock`, the Swift packages and their `Package.resolved`) and keep the two-week release-age rule (`docs/dependencies.md`).
- Do not commit, push, tag, publish or rewrite history unless explicitly asked. Never move or delete a published tag.
- Work is not done until `uv run pytest` passes. Report actual results, including failures.
- Any change under `template/` or to `copier.yml` needs a matching test. Record user-visible changes in `CHANGELOG.md`.

## Template rules

- Output contains no secrets, credentials, team identifiers, provisioning material, usernames or home-directory paths.
- Only files that need substitution get the `.jinja` suffix. The Xcode project, the Swift sources and the generated client
  are verbatim; names, bundle identifier and API address live in `Config/*.xcconfig`.
- The client in `Sources/APIClient` is generated (`ios/scripts/generate-client.sh`) from `Contract/openapi.json`, which is a
  copy of a **published** `web-core-template` contract (`tools/web_contract.json` records which). Never edit either by hand.
- Release is https only, with no App Transport Security exception; Debug may use `NSAllowsLocalNetworking`. Certificate
  validation is never disabled or pinned. The session token is only ever in the Keychain.
- No `_tasks`, `_migrations` or `_jinja_extensions` in `copier.yml` (they would need `--trust`).

## Destructive commands

Never run recursive or forced removal by hand (`rm -r`, `rm -rf`), `find ... -delete`, `git clean`,
`git reset --hard`, forced pushes or recursive `chmod`/`chown`; a test fails if any appear here. Never hide a
state-changing command's errors.
