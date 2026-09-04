#!/bin/bash
# Builds Knurl and packages it for a GitHub release.
#
# The app is not signed with a Developer ID, so this produces a plain zip and
# the README tells people how to get past Gatekeeper. Notarising would need a
# paid Apple Developer account.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.0.0" >&2
    exit 2
fi

"$ROOT/scripts/build-app.sh" release

DIST="$ROOT/build/Knurl-$VERSION.zip"
rm -f "$DIST"
# ditto keeps the bundle's structure and the ad-hoc signature intact.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/Knurl.app" "$DIST"

echo "Packaged $DIST"
echo
echo "To publish, with the GitHub CLI:"
echo "  gh release create v$VERSION \"$DIST\" --title \"Knurl $VERSION\" --notes-file <notes.md>"
