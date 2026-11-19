#!/bin/sh
# Static checks over the iOS sources: nothing that would weaken transport security or leak a credential.
# usage: ios/scripts/check-static.sh   (exit 1 with the offending lines on a finding)
set -eu
cd "$(dirname "$0")/.."
FAILED=0
flag() { # description, pattern, paths...
  DESC="$1"; PATTERN="$2"; shift 2
  if grep -rnE --exclude-dir=.build --exclude-dir=.derived-data --exclude-dir=.git --exclude-dir=.swiftpm --exclude=check-static.sh "$PATTERN" "$@" 2>/dev/null; then echo "  ^ $DESC" >&2; FAILED=1; fi
}
SOURCES="App Packages/AppCore/Sources/AppCore Config"
flag "global ATS opt-out" 'NSAllowsArbitraryLoads|NSExceptionDomains|NSAllowsInsecureHTTPLoads' $SOURCES
flag "certificate validation must stay with the system" 'serverTrust|didReceiveChallenge|URLCredential\(trust|SecTrustSetExceptions|allowsAnyHTTPSCertificate' $SOURCES
flag "the token or password in a log or print" '(print|NSLog|os_log|Logger|debugPrint|dump)\(.*(token|password|bearer|Authorization)' $SOURCES
flag "credentials in UserDefaults" 'UserDefaults.*(token|password|session)|(token|password).*UserDefaults' $SOURCES
flag "a token or password written to a file" '(write|FileManager).*(token|password)' $SOURCES
flag "a hard-coded http URL (the API address is configuration)" 'URL\(string: *"http' $SOURCES
flag "a hard-coded secret, key or personal path" 'sk_live|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|/Users/[A-Za-z]|gh[pousr]_[A-Za-z0-9]{20,}' App Packages Config AppTests scripts Contract
flag "a development team committed to the project" 'DEVELOPMENT_TEAM *= *[A-Z0-9]{6,}' Config App.xcodeproj
flag "the service-role or database credentials in the iOS layer" 'service_role|SERVICE_ROLE|DATABASE_URL|DATABASE_RUNTIME_URL|BETTER_AUTH_SECRET' App Packages/AppCore/Sources Config
[ "$FAILED" = 0 ] && echo "static checks passed"
exit "$FAILED"
