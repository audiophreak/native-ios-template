# Contributing

Thanks for your interest in native-ios-template. It is a small, independently maintained project, so
focused changes with tests are the easiest to review.

## Development setup

Requirements: Git, [uv](https://docs.astral.sh/uv/), Python 3.12 or later, and for the full suite a Mac
with Xcode 26 and an iOS Simulator runtime.

```bash
git clone https://github.com/audiophreak/native-ios-template.git
cd native-ios-template
uv sync --locked
uv run pytest -m "not xcode"   # rendering, layering, static rules, pins
uv run pytest                  # everything, including swift test and xcodebuild for the simulator
```

## Ground rules

The full rules are in [AGENTS.md](AGENTS.md); they apply to people and coding agents alike. In short:

- Open an issue first for anything beyond a small fix.
- Any change under `template/` or to `copier.yml` needs a matching test. Record user-visible changes in
  `CHANGELOG.md`.
- Do not add, upgrade or remove Swift packages or Python dependencies without discussion; pins are
  exact and at least two weeks old (`docs/dependencies.md`).
- Never edit the generated client or the copied contract by hand; regenerate them.
- Rendered output must never contain secrets, team identifiers, signing material, usernames or
  machine-specific paths.
- Never add recursive or forced deletes or hidden errors.

## Pull requests

CI renders and checks the template on Linux and builds and tests the generated app on a macOS runner
for every pull request. Releases are annotated git tags created by the maintainer after CI passes on
`main` (`docs/maintaining.md`).

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
Report security issues privately as described in [SECURITY.md](SECURITY.md).
