#!/bin/zsh
# Checks the built bundle build/MacLabel.app (run scripts/build-app.sh first).
# Exits non-zero when anything is missing or wrong. Never talks to a printer.
set -u
cd "${0:A:h}/.."
APP="${1:-build/MacLabel.app}"
failures=0
pass() { print -- "PASS  $1" }
fail() { print -- "FAIL  $1"; failures=$((failures + 1)) }

if [[ ! -d "$APP" ]]; then
    fail "bundle $APP missing (run scripts/build-app.sh)"
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Exactly the four allowed entitlements, nothing about the network.
if codesign -d --entitlements "$tmp/app.xml" --xml "$APP" 2>/dev/null && [[ -s "$tmp/app.xml" ]]; then
    actual=$(/usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(sorted((k, v if not isinstance(v, list) else tuple(v)) for k, v in d.items()))
' "$tmp/app.xml")
    expected="[('com.apple.security.app-sandbox', True), ('com.apple.security.device.usb', True), ('com.apple.security.files.user-selected.read-only', True), ('com.apple.security.temporary-exception.iokit-user-client-class', ('AppleUSBHostFrameworkInterfaceClient',))]"
    if [[ "$actual" == "$expected" ]]; then pass "app entitlements are exactly the four allowed ones"
    else fail "app entitlements differ: $actual"; fi
    if grep -qi network "$tmp/app.xml"; then fail "app entitlements mention network"
    else pass "no network entitlement"; fi
else
    fail "codesign could not read the app entitlements"
fi
if codesign --verify --deep --strict "$APP" 2>"$tmp/verify.txt"; then pass "codesign --verify --deep --strict"
else fail "codesign verify: $(cat "$tmp/verify.txt")"; fi

# The app's own executable must survive next to the CLI (case-insensitive volume: not "MacLabel").
exe=$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist" 2>/dev/null)
if [[ -n "$exe" && "${exe:l}" != maclabel && -x "$APP/Contents/MacOS/$exe" ]]; then pass "app executable Contents/MacOS/$exe"
else fail "app executable '$exe' missing or clashes with the CLI"; fi

# 2. Embedded CLI, not sandboxed, works through a symlink from outside the bundle.
CLI="$APP/Contents/MacOS/maclabel"
if [[ -x "$CLI" ]]; then
    pass "Contents/MacOS/maclabel exists"
    codesign -d --entitlements "$tmp/cli.xml" --xml "$CLI" 2>/dev/null
    if [[ -s "$tmp/cli.xml" ]] && grep -q "app-sandbox" "$tmp/cli.xml"; then fail "CLI is sandboxed"
    else pass "CLI has no sandbox entitlement"; fi
    ln -s "${CLI:A}" "$tmp/maclabel"
    out=$("$tmp/maclabel" rolls search 32x57 2>&1); code=$?
    if [[ $code -eq 0 && "$out" == *11354* ]]; then pass "symlinked 'maclabel rolls search 32x57' finds 11354"
    else fail "symlinked CLI: exit $code, output: $out"; fi
else
    fail "Contents/MacOS/maclabel missing"
fi

# 3. Service entry.
if plutil -extract NSServices xml1 -o - "$APP/Contents/Info.plist" >/dev/null 2>&1; then pass "Info.plist has NSServices"
else fail "Info.plist lacks NSServices"; fi

# 4. No network code.
if hits=$(grep -rnE "URLSession|import Network" Sources App 2>/dev/null); then fail "network code found: $hits"
else pass "no URLSession / import Network in Sources or App"; fi

if (( failures > 0 )); then
    print -- "verify-app: $failures check(s) failed"
    exit 1
fi
print -- "verify-app: all checks passed"
