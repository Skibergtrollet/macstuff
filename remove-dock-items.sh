#!/bin/bash

# Apps to remove from the macOS Dock
APPS_TO_REMOVE=(
    "Safari"
    "Mail"
    "Messages"
    "FaceTime"
    "Calendar"
    "Contacts"
    "Maps"
    "Photos"
    "Reminders"
    "Freeform"
    "TV"
    "Music"
    "App Store"
)

DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"

echo "Cleaning macOS Dock..."

for APP in "${APPS_TO_REMOVE[@]}"; do
    echo "Checking: $APP"

    while true; do
        INDEX=$(/usr/libexec/PlistBuddy -c "Print persistent-apps" "$DOCK_PLIST" 2>/dev/null |
            grep -n "\"$APP\"" |
            head -1 |
            cut -d: -f1)

        # App not found
        [[ -z "$INDEX" ]] && break

        # Convert grep line number to approximate plist array index
        # Safer approach below uses Dock tile labels instead.
        break
    done
done

# Remove entries by tile-data:file-label
python3 <<'PY'
import plistlib
from pathlib import Path

plist_path = Path.home() / "Library/Preferences/com.apple.dock.plist"

remove = {
    "Safari",
    "Mail",
    "Messages",
    "FaceTime",
    "Calendar",
    "Contacts",
    "Maps",
    "Photos",
    "Reminders",
    "Freeform",
    "TV",
    "Music",
    "App Store",
}

with plist_path.open("rb") as f:
    plist = plistlib.load(f)

apps = plist.get("persistent-apps", [])

original_count = len(apps)

plist["persistent-apps"] = [
    item
    for item in apps
    if item.get("tile-data", {}).get("file-label") not in remove
]

removed = original_count - len(plist["persistent-apps"])

with plist_path.open("wb") as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)

print(f"Removed {removed} Dock item(s).")
PY

# Restart Dock so changes appear
killall Dock

echo "Done."