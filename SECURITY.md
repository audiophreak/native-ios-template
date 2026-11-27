# Security policy

## Supported versions

Security fixes are made for the latest template release (the newest `vMAJOR.MINOR.PATCH` tag) only.
Generated projects receive fixes by updating the native layer (`devkit upgrade PROJECT --layer native`).

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: **Security › Report a vulnerability**
(https://github.com/audiophreak/native-ios-template/security/advisories/new). Do not open a public issue
for a suspected vulnerability.

Include the template release, your Xcode and iOS versions and the smallest reproduction you can. Do not
include tokens, session cookies, signing material (certificates, `.p12`, provisioning profiles) or other
secrets. This is an independently maintained project: expect an acknowledgement within about a week.
Fixes are released as soon as practical, with credit if you would like it.

## Security posture

- The session token is stored only in the Keychain. Release builds use https only, with no App
  Transport Security exception; only Debug builds may use cleartext to `localhost`. Certificate
  validation is never disabled or pinned.
- Rendered output contains no secrets, credentials, team identifiers, provisioning material,
  usernames or home-directory paths; tests scan every rendered file.
- The typed API client is generated from a published `web-core-template` contract and is never
  edited by hand.
- Swift packages are exact-pinned (`Package.resolved`) with a two-week release-age rule
  (`docs/dependencies.md`). The template uses no Copier `_tasks`, `_migrations` or
  `_jinja_extensions`, so it never needs `--trust`.
- CI uses read-only `GITHUB_TOKEN` permissions, `persist-credentials: false`, actions pinned to full
  commit SHAs, stores no secrets and does not run on `pull_request_target`.
