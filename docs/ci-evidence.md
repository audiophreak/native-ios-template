# CI evidence

`.github/workflows/ci.yml` runs on every pull request and on `main`:

| Job | Runner | Proves |
|---|---|---|
| `template` | ubuntu-24.04 | rendering, validators, layering (no web file touched), static rules, pins and ages, `copier update` of the layer alone |
| `xcode` | macos-26, newest installed Xcode 26 | static checks, contract checksum, **regeneration of the client with zero diff**, `swift test`, hosted app tests and package tests on an iOS Simulator, Release requires https, the Xcode-dependent template tests |

No signing certificate, provisioning profile, App Store credential or secret is used or needed.

**The real end-to-end scenario is a local release gate**, not a CI job: it needs Docker (PostgreSQL or the Supabase stack), Node 26,
a production build of the web part and a simulator at the same time, which GitHub's macOS runners do not provide reliably
(no Docker). It is run by `ios/scripts/e2e.mjs` before every release, for both database providers; results are in the release notes.
