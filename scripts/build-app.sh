#!/bin/zsh
# Builds build/MacLabel.app (Release, ad-hoc signed) from App/project.yml.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy to ~/Applications and refresh the Services menu
set -euo pipefail
cd "${0:A:h}/.."

install=false
for arg in "$@"; do
    case "$arg" in
        --install) install=true ;;
        *) print -u2 "usage: scripts/build-app.sh [--install]"; exit 64 ;;
    esac
done

xcodegen generate --spec App/project.yml
xcodebuild -project App/MacLabel.xcodeproj -scheme MacLabel -configuration Release \
    -derivedDataPath build/dd clean build

rm -rf build/MacLabel.app
ditto build/dd/Build/Products/Release/MacLabel.app build/MacLabel.app
codesign --verify --deep --strict --verbose=2 build/MacLabel.app
print "Entitlements of MacLabel.app:"
codesign -d --entitlements - --xml build/MacLabel.app 2>/dev/null | plutil -p -
print "Entitlements of the embedded maclabel:"
codesign -d --entitlements - --xml build/MacLabel.app/Contents/MacOS/maclabel 2>/dev/null | plutil -p - 2>/dev/null || print "(none)"

if $install; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/MacLabel.app
    ditto build/MacLabel.app ~/Applications/MacLabel.app
    /System/Library/CoreServices/pbs -update
    print "Installed to ~/Applications/MacLabel.app (Services menu refreshed)."
fi
print "Built build/MacLabel.app"
