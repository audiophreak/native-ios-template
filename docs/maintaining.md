# Maintaining

- **Releases** are annotated tags on `main` after a pull request with passing CI, a normal merge commit and a green CI run on `main`.
  Never move or delete a published tag. 0.x minor bumps may be breaking.
- **Bumping the web contract** (when `web-core-template` releases an API change): copy the published web release's
  `openapi/openapi.json` into `template/ios/Contract/`, write its checksum to `openapi.sha256` and to `tools/web_contract.json`
  (with the release), run `template/ios/scripts/generate-client.sh` from a rendered project (or in place), fix what the app needs, release.
- **Bumping a Swift dependency:** `docs/dependencies.md`.
- **The Xcode project** is generated: edit `tools/gen_pbxproj.py` and run it; a test fails if the committed project differs.
- **End to end** (needs Docker, Node 26 and a simulator; not run on GitHub's macOS runners): from a project generated with
  `devkit new … --profile native-ios`, `node ios/scripts/e2e.mjs`. It is a release gate: record its result in `docs/ci-evidence.md`.
