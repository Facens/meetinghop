#!/bin/bash
# Source-tree assertions. CI runs this on every push and pull request; a
# contributor can run it by hand before opening one. Ported from AgentMenu's
# packaging/check-source.sh without the licence-header check: MeetingHop is
# MIT, carries no headers, and is not asked to grow them.
#
#   Kit purity   MeetingHopKit imports no AppKit, SwiftUI, EventKit or Sparkle,
#                and the package manifest declares no Sparkle dependency on it
#                — the manifest check fires before anyone has written the
#                import, which an import grep alone cannot
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
fail() { echo "  ✗ $1" >&2; failures=$((failures + 1)); }

echo "Kit purity: imports"
# Any spelling of the import: indented inside an #if, behind an attribute
# (@preconcurrency, @_exported), scoped (import class AppKit.NSImage), or
# through Cocoa, which re-exports AppKit.
if hits="$(grep -rlE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?(AppKit|Cocoa|SwiftUI|EventKit|Sparkle)([.[:space:]]|$)' Sources/MeetingHopKit)"; then
    while IFS= read -r file; do fail "$file imports AppKit, Cocoa, SwiftUI, EventKit or Sparkle"; done <<< "$hits"
fi

echo "Kit purity: manifest"
MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT
if ! swift package dump-package > "$MANIFEST" 2>/dev/null; then
    fail "swift package dump-package failed; the manifest could not be inspected"
elif ! python3 - "$MANIFEST" <<'PY'
import json, sys
package = json.load(open(sys.argv[1]))
kit = next((t for t in package["targets"] if t["name"] == "MeetingHopKit"), None)
if kit is None:
    print("  no MeetingHopKit target in the manifest", file=sys.stderr)
    sys.exit(1)
names = []
for dep in kit.get("dependencies", []):
    for kind, value in dep.items():
        names.append(str(value[0]) if isinstance(value, list) else str(value))
bad = [n for n in names if "sparkle" in n.lower()]
if bad:
    print("  MeetingHopKit declares a Sparkle dependency: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
PY
then
    fail "the manifest attaches Sparkle to MeetingHopKit"
fi

if [ "$failures" -gt 0 ]; then
    echo "source checks: FAIL ($failures)" >&2
    exit 1
fi
echo "source checks: ok"
