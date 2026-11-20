#!/bin/bash

###############################################################################
# Remove applications from the macOS Dock
#
# Designed for:
#   - Jamf Pro policies
#   - Microsoft Intune macOS shell scripts
#   - Other device-management systems that execute scripts as root
#
# Features:
#   - Detects the currently logged-in GUI user
#   - Does not modify root's Dock
#   - Language-independent bundle-ID matching
#   - Does not require Python or third-party tools
#   - Creates a backup before making changes
#   - Safely exits at the login window
#   - Returns useful exit codes for Jamf and Intune reporting
###############################################################################

set -u
set -o pipefail

readonly SCRIPT_NAME="Configure macOS Dock"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"
readonly MAX_LOGIN_WAIT_SECONDS=60
readonly LOGIN_CHECK_INTERVAL=5

###############################################################################
# Configuration
###############################################################################

# Bundle identifiers to remove from the Dock.
#
# These identifiers remain the same regardless of whether macOS is configured
# in Norwegian, English, Swedish, German, or another language.

REMOVE_BUNDLE_IDS=(
    "com.apple.Safari"
    "com.apple.mail"
    "com.apple.MobileSMS"
    "com.apple.FaceTime"
    "com.apple.iCal"
    "com.apple.AddressBook"
    "com.apple.Maps"
    "com.apple.Photos"
    "com.apple.reminders"
    "com.apple.freeform"
    "com.apple.Music"
    "com.apple.TV"
    "com.apple.AppStore"
    "com.apple.games" 
    "com.apple.mobilephone"
    "com.apple.ScreenContinuity"
    "com.apple.Notes"
)

# Set to true to disable "Show suggested and recent apps in Dock".
DISABLE_RECENT_APPS=true

# Set to true if the script should wait briefly for a user to log in.
# Recommended for Intune scripts that may run shortly after enrollment.
WAIT_FOR_LOGGED_IN_USER=true

###############################################################################
# Logging
###############################################################################

log() {
    local message="$1"
    printf '%s [%s] %s\n' \
        "$(/bin/date '+%Y-%m-%d %H:%M:%S')" \
        "$SCRIPT_NAME" \
        "$message"
}

###############################################################################
# Validation
###############################################################################

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
    log "ERROR: This script must run as root."
    exit 1
fi

if [[ ! -x "$PLIST_BUDDY" ]]; then
    log "ERROR: PlistBuddy was not found at $PLIST_BUDDY."
    exit 1
fi

###############################################################################
# Logged-in user detection
###############################################################################

get_logged_in_user() {
    /usr/bin/stat -f '%Su' /dev/console 2>/dev/null
}

is_valid_gui_user() {
    local user="${1:-}"

    [[ -n "$user" ]] &&
    [[ "$user" != "root" ]] &&
    [[ "$user" != "loginwindow" ]] &&
    [[ "$user" != "_mbsetupuser" ]]
}

logged_in_user="$(get_logged_in_user)"
waited_seconds=0

if [[ "$WAIT_FOR_LOGGED_IN_USER" == "true" ]]; then
    while ! is_valid_gui_user "$logged_in_user"; do
        if (( waited_seconds >= MAX_LOGIN_WAIT_SECONDS )); then
            break
        fi

        log "No eligible GUI user detected. Waiting..."
        /bin/sleep "$LOGIN_CHECK_INTERVAL"

        waited_seconds=$((waited_seconds + LOGIN_CHECK_INTERVAL))
        logged_in_user="$(get_logged_in_user)"
    done
fi

if ! is_valid_gui_user "$logged_in_user"; then
    log "No eligible GUI user is logged in. Nothing to configure."
    exit 0
fi

###############################################################################
# Resolve the user's UID and home directory
###############################################################################

logged_in_uid="$(/usr/bin/id -u "$logged_in_user" 2>/dev/null || true)"

if [[ -z "$logged_in_uid" ]]; then
    log "ERROR: Could not resolve UID for user: $logged_in_user"
    exit 1
fi

user_home="$(
    /usr/bin/dscl . \
        -read "/Users/$logged_in_user" NFSHomeDirectory 2>/dev/null |
    /usr/bin/awk '{print $2}'
)"

# Fallback for local/mobile accounts where dscl does not return a home path.
if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    user_home="$(/usr/bin/eval echo "~$logged_in_user" 2>/dev/null || true)"
fi

if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    log "ERROR: Could not resolve a valid home directory for $logged_in_user."
    exit 1
fi

dock_plist="$user_home/Library/Preferences/com.apple.dock.plist"

log "Logged-in user: $logged_in_user"
log "User UID: $logged_in_uid"
log "Home directory: $user_home"
log "Dock plist: $dock_plist"

###############################################################################
# Helpers
###############################################################################

run_as_user() {
    /bin/launchctl asuser "$logged_in_uid" \
        /usr/bin/sudo -u "$logged_in_user" -- "$@"
}

bundle_id_is_configured_for_removal() {
    local detected_bundle_id="$1"
    local configured_bundle_id

    for configured_bundle_id in "${REMOVE_BUNDLE_IDS[@]}"; do
        if [[ "$detected_bundle_id" == "$configured_bundle_id" ]]; then
            return 0
        fi
    done

    return 1
}

get_dock_item_bundle_id() {
    local index="$1"
    local bundle_id=""
    local app_url=""
    local app_path=""

    # Most Dock application entries contain a bundle-identifier value.
    bundle_id="$(
        "$PLIST_BUDDY" \
            -c "Print :persistent-apps:${index}:tile-data:bundle-identifier" \
            "$dock_plist" 2>/dev/null || true
    )"

    if [[ -n "$bundle_id" ]]; then
        printf '%s\n' "$bundle_id"
        return 0
    fi

    # Fallback for Dock entries without bundle-identifier metadata.
    app_url="$(
        "$PLIST_BUDDY" \
            -c "Print :persistent-apps:${index}:tile-data:file-data:_CFURLString" \
            "$dock_plist" 2>/dev/null || true
    )"

    if [[ -z "$app_url" ]]; then
        return 1
    fi

    app_path="${app_url#file://}"

    # Decode the common URL encodings used in application paths.
    app_path="${app_path//%20/ }"
    app_path="${app_path//%23/#}"
    app_path="${app_path//%25/%}"

    app_path="${app_path%/}"

    if [[ ! -e "$app_path" ]]; then
        return 1
    fi

    bundle_id="$(
        /usr/bin/mdls \
            -raw \
            -name kMDItemCFBundleIdentifier \
            "$app_path" 2>/dev/null |
        /usr/bin/tr -d '"'
    )"

    if [[ -z "$bundle_id" || "$bundle_id" == "(null)" ]]; then
        return 1
    fi

    printf '%s\n' "$bundle_id"
}

###############################################################################
# Prepare Dock preferences
###############################################################################

preferences_directory="$user_home/Library/Preferences"

/bin/mkdir -p "$preferences_directory"
/usr/sbin/chown "$logged_in_user":staff "$preferences_directory" 2>/dev/null || true

# If the Dock plist does not exist yet, start the Dock once so macOS creates it.
if [[ ! -f "$dock_plist" ]]; then
    log "Dock preferences do not exist yet. Starting Dock to initialize them."

    run_as_user /usr/bin/open -gja Dock 2>/dev/null || true
    /bin/sleep 5
fi

if [[ ! -f "$dock_plist" ]]; then
    log "No Dock plist is available yet. The script will retry at the next management check-in."
    exit 0
fi

###############################################################################
# Back up the Dock plist
###############################################################################

timestamp="$(/bin/date '+%Y%m%d-%H%M%S')"
backup_plist="${dock_plist}.backup-${timestamp}"

/bin/cp -p "$dock_plist" "$backup_plist"

if [[ $? -ne 0 ]]; then
    log "ERROR: Could not create Dock preference backup."
    exit 1
fi

log "Backup created: $backup_plist"

###############################################################################
# Determine the number of persistent application entries
###############################################################################

persistent_apps_output="$(
    "$PLIST_BUDDY" \
        -c "Print :persistent-apps" \
        "$dock_plist" 2>/dev/null || true
)"

if [[ -z "$persistent_apps_output" ]]; then
    log "No persistent application section was found in the Dock plist."
    exit 0
fi

# PlistBuddy prints one 'Dict {' line for each Dock application entry.
dock_item_count="$(
    printf '%s\n' "$persistent_apps_output" |
    /usr/bin/grep -c '^[[:space:]]*Dict {' || true
)"

if [[ ! "$dock_item_count" =~ ^[0-9]+$ ]]; then
    log "ERROR: Could not determine the number of Dock entries."
    exit 1
fi

log "Found $dock_item_count persistent Dock application entries."

###############################################################################
# Find entries to remove
###############################################################################

indexes_to_remove=()
removed_bundle_ids=()

for ((index=0; index<dock_item_count; index++)); do
    bundle_id="$(get_dock_item_bundle_id "$index" || true)"

    if [[ -z "$bundle_id" ]]; then
        log "Dock index $index has no resolvable bundle ID; keeping it."
        continue
    fi

    if bundle_id_is_configured_for_removal "$bundle_id"; then
        log "Marked for removal: $bundle_id at Dock index $index"
        indexes_to_remove+=("$index")
        removed_bundle_ids+=("$bundle_id")
    else
        log "Keeping: $bundle_id"
    fi
done

###############################################################################
# Stop the user's Dock before modifying its preferences
###############################################################################

if (( ${#indexes_to_remove[@]} > 0 )); then
    log "Stopping Dock for $logged_in_user."

    run_as_user /usr/bin/killall Dock 2>/dev/null || true
    /bin/sleep 1

    # Delete in reverse order so array indexes remain valid.
    for ((i=${#indexes_to_remove[@]}-1; i>=0; i--)); do
        index="${indexes_to_remove[$i]}"

        if "$PLIST_BUDDY" \
            -c "Delete :persistent-apps:${index}" \
            "$dock_plist" 2>/dev/null; then

            log "Removed Dock entry at index $index."
        else
            log "ERROR: Failed to remove Dock entry at index $index."
            log "Restoring original Dock preferences from backup."

            /bin/cp -p "$backup_plist" "$dock_plist"
            /usr/sbin/chown "$logged_in_user":staff "$dock_plist"

            run_as_user /usr/bin/killall Dock 2>/dev/null || true
            exit 1
        fi
    done

    /usr/sbin/chown "$logged_in_user":staff "$dock_plist"
    /bin/chmod 600 "$dock_plist"

    log "Removed ${#removed_bundle_ids[@]} Dock application entries."
else
    log "No configured applications were present in the Dock."
fi

###############################################################################
# Additional Dock preferences
###############################################################################

if [[ "$DISABLE_RECENT_APPS" == "true" ]]; then
    if run_as_user \
        /usr/bin/defaults write com.apple.dock show-recents -bool false; then

        log "Disabled suggested and recent applications in the Dock."
    else
        log "WARNING: Could not disable recent applications."
    fi
fi

###############################################################################
# Restart the user's Dock
###############################################################################

log "Restarting Dock for $logged_in_user."

run_as_user /usr/bin/killall Dock 2>/dev/null || true

# If Dock was not running, launch it through the user's GUI session.
run_as_user /usr/bin/open -gja Dock 2>/dev/null || true

log "Dock configuration completed successfully."
exit 0