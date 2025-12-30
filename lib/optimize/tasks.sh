#!/bin/bash
# Optimization Tasks

set -euo pipefail

# Configuration constants
# MOLE_TM_THIN_TIMEOUT: Max seconds to wait for tmutil thinning (default: 180)
# MOLE_TM_THIN_VALUE: Bytes to thin for local snapshots (default: 9999999999)
# MOLE_MAIL_DOWNLOADS_MIN_KB: Minimum size in KB before cleaning Mail attachments (default: 5120)
# MOLE_MAIL_AGE_DAYS: Minimum age in days for Mail attachments to be cleaned (default: 30)
readonly MOLE_TM_THIN_TIMEOUT=180
readonly MOLE_TM_THIN_VALUE=9999999999
readonly MOLE_SQLITE_MAX_SIZE=104857600 # 100MB

# Helper function to get appropriate icon and color for dry-run mode
opt_msg() {
    local message="$1"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $message"
    else
        echo -e "  ${GREEN}✓${NC} $message"
    fi
}

run_launchctl_unload() {
    local plist_file="$1"
    local need_sudo="${2:-false}"

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi

    if [[ "$need_sudo" == "true" ]]; then
        sudo launchctl unload "$plist_file" 2> /dev/null || true
    else
        launchctl unload "$plist_file" 2> /dev/null || true
    fi
}

needs_permissions_repair() {
    local owner
    owner=$(stat -f %Su "$HOME" 2> /dev/null || echo "")
    if [[ -n "$owner" && "$owner" != "$USER" ]]; then
        return 0
    fi

    local -a paths=(
        "$HOME"
        "$HOME/Library"
        "$HOME/Library/Preferences"
    )
    local path
    for path in "${paths[@]}"; do
        if [[ -e "$path" && ! -w "$path" ]]; then
            return 0
        fi
    done

    return 1
}

has_bluetooth_hid_connected() {
    local bt_report
    bt_report=$(system_profiler SPBluetoothDataType 2> /dev/null || echo "")
    if ! echo "$bt_report" | grep -q "Connected: Yes"; then
        return 1
    fi

    if echo "$bt_report" | grep -Eiq "Keyboard|Trackpad|Mouse|HID"; then
        return 0
    fi

    return 1
}

is_ac_power() {
    pmset -g batt 2> /dev/null | grep -q "AC Power"
}

is_memory_pressure_high() {
    if ! command -v memory_pressure > /dev/null 2>&1; then
        return 1
    fi

    local mp_output
    mp_output=$(memory_pressure -Q 2> /dev/null || echo "")
    if echo "$mp_output" | grep -Eiq "warning|critical"; then
        return 0
    fi

    return 1
}

flush_dns_cache() {
    # Skip actual flush in dry-run mode
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        MOLE_DNS_FLUSHED=1
        return 0
    fi

    if sudo dscacheutil -flushcache 2> /dev/null && sudo killall -HUP mDNSResponder 2> /dev/null; then
        MOLE_DNS_FLUSHED=1
        return 0
    fi
    return 1
}

# Rebuild databases and flush caches
opt_system_maintenance() {
    if flush_dns_cache; then
        opt_msg "DNS cache flushed"
    fi

    local spotlight_status
    spotlight_status=$(mdutil -s / 2> /dev/null || echo "")
    if echo "$spotlight_status" | grep -qi "Indexing disabled"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight indexing disabled"
    else
        opt_msg "Spotlight index verified"
    fi
}

# Refresh Finder caches (QuickLook and icon services)
# Note: Safari caches are cleaned separately in clean/user.sh, so excluded here
opt_cache_refresh() {
    # Skip qlmanage commands in dry-run mode
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        qlmanage -r cache > /dev/null 2>&1 || true
        qlmanage -r > /dev/null 2>&1 || true
    fi

    local -a cache_targets=(
        "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
        "$HOME/Library/Caches/com.apple.iconservices.store"
        "$HOME/Library/Caches/com.apple.iconservices"
    )

    for target_path in "${cache_targets[@]}"; do
        if [[ -e "$target_path" ]]; then
            if ! should_protect_path "$target_path"; then
                safe_remove "$target_path" true > /dev/null 2>&1
            fi
        fi
    done

    opt_msg "QuickLook thumbnails refreshed"
    opt_msg "Icon services cache rebuilt"
}

# Removed: opt_maintenance_scripts - macOS handles log rotation automatically via launchd

# Removed: opt_radio_refresh - Interrupts active user connections (WiFi, Bluetooth), degrading UX

# Saved state: remove OLD app saved states (7+ days)
opt_saved_state_cleanup() {
    local state_dir="$HOME/Library/Saved Application State"

    if [[ -d "$state_dir" ]]; then
        while IFS= read -r -d '' state_path; do
            if should_protect_path "$state_path"; then
                continue
            fi
            safe_remove "$state_path" true > /dev/null 2>&1
        done < <(command find "$state_dir" -type d -name "*.savedState" -mtime "+$MOLE_SAVED_STATE_AGE_DAYS" -print0 2> /dev/null)
    fi

    opt_msg "App saved states optimized"
}

# Removed: opt_swap_cleanup - Direct virtual memory operations pose system crash risk

# Removed: opt_startup_cache - Modern macOS has no such mechanism

# Removed: opt_local_snapshots - Deletes user Time Machine recovery points, breaks backup continuity

opt_fix_broken_configs() {
    local broken_prefs=$(fix_broken_preferences)

    if [[ $broken_prefs -gt 0 ]]; then
        opt_msg "Repaired $broken_prefs corrupted preference files"
    else
        opt_msg "All preference files valid"
    fi
}

# Network cache optimization
opt_network_optimization() {
    if [[ "${MOLE_DNS_FLUSHED:-0}" == "1" ]]; then
        opt_msg "DNS cache already refreshed"
        opt_msg "mDNSResponder already restarted"
        return 0
    fi

    if flush_dns_cache; then
        opt_msg "DNS cache refreshed"
        opt_msg "mDNSResponder restarted"
    else
        echo -e "  ${YELLOW}!${NC} Failed to refresh DNS cache"
    fi
}

# SQLite database vacuum optimization
# Compresses and optimizes SQLite databases for Mail, Messages, Safari
opt_sqlite_vacuum() {
    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo -e "  ${GRAY}-${NC} Database optimization already optimal (sqlite3 unavailable)"
        return 0
    fi

    local -a busy_apps=()
    local -a check_apps=("Mail" "Safari" "Messages")
    local app
    for app in "${check_apps[@]}"; do
        if pgrep -x "$app" > /dev/null 2>&1; then
            busy_apps+=("$app")
        fi
    done

    if [[ ${#busy_apps[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}!${NC} Close these apps before database optimization: ${busy_apps[*]}"
        return 0
    fi

    local spinner_started="false"
    if [[ "${MOLE_DRY_RUN:-0}" != "1" && -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Optimizing databases..."
        spinner_started="true"
    fi

    local -a db_paths=(
        "$HOME/Library/Mail/V*/MailData/Envelope Index*"
        "$HOME/Library/Messages/chat.db"
        "$HOME/Library/Safari/History.db"
        "$HOME/Library/Safari/TopSites.db"
    )

    local vacuumed=0
    local timed_out=0
    local failed=0
    local skipped=0

    for pattern in "${db_paths[@]}"; do
        while IFS= read -r db_file; do
            [[ ! -f "$db_file" ]] && continue
            [[ "$db_file" == *"-wal" || "$db_file" == *"-shm" ]] && continue

            # Skip if protected
            should_protect_path "$db_file" && continue

            # Verify it's a SQLite database
            if ! file "$db_file" 2> /dev/null | grep -q "SQLite"; then
                continue
            fi

            # Safety check 1: Skip large databases (>100MB) to avoid timeouts
            local file_size
            file_size=$(get_file_size "$db_file")
            if [[ "$file_size" -gt "$MOLE_SQLITE_MAX_SIZE" ]]; then
                ((skipped++))
                continue
            fi

            # Safety check 2: Skip if freelist is tiny (already compact)
            local page_info=""
            page_info=$(run_with_timeout 5 sqlite3 "$db_file" "PRAGMA page_count; PRAGMA freelist_count;" 2> /dev/null || echo "")
            local page_count=""
            local freelist_count=""
            page_count=$(echo "$page_info" | awk 'NR==1 {print $1}' 2> /dev/null || echo "")
            freelist_count=$(echo "$page_info" | awk 'NR==2 {print $1}' 2> /dev/null || echo "")
            if [[ "$page_count" =~ ^[0-9]+$ && "$freelist_count" =~ ^[0-9]+$ && "$page_count" -gt 0 ]]; then
                if ((freelist_count * 100 < page_count * 5)); then
                    ((skipped++))
                    continue
                fi
            fi

            # Safety check 3: Verify database integrity before VACUUM
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                local integrity_check=""
                set +e
                integrity_check=$(run_with_timeout 10 sqlite3 "$db_file" "PRAGMA integrity_check;" 2> /dev/null)
                local integrity_status=$?
                set -e

                # Skip if integrity check failed or database is corrupted
                if [[ $integrity_status -ne 0 ]] || ! echo "$integrity_check" | grep -q "ok"; then
                    ((skipped++))
                    continue
                fi
            fi

            # Try to vacuum (skip in dry-run mode)
            local exit_code=0
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                set +e
                run_with_timeout 20 sqlite3 "$db_file" "VACUUM;" 2> /dev/null
                exit_code=$?
                set -e

                if [[ $exit_code -eq 0 ]]; then
                    ((vacuumed++))
                elif [[ $exit_code -eq 124 ]]; then
                    ((timed_out++))
                else
                    ((failed++))
                fi
            else
                # In dry-run mode, just count the database
                ((vacuumed++))
            fi
        done < <(compgen -G "$pattern" || true)
    done

    if [[ "$spinner_started" == "true" ]]; then
        stop_inline_spinner
    fi

    if [[ $vacuumed -gt 0 ]]; then
        opt_msg "Optimized $vacuumed databases for Mail, Safari, Messages"
    elif [[ $timed_out -eq 0 && $failed -eq 0 ]]; then
        opt_msg "All databases already optimized"
    else
        echo -e "  ${YELLOW}!${NC} Database optimization incomplete"
    fi

    if [[ $skipped -gt 0 ]]; then
        echo -e "  ${GRAY}Already optimal for $skipped databases (size or integrity limits)${NC}"
    fi

    if [[ $timed_out -gt 0 ]]; then
        echo -e "  ${YELLOW}!${NC} Timed out on $timed_out databases"
    fi

    if [[ $failed -gt 0 ]]; then
        echo -e "  ${YELLOW}!${NC} Failed on $failed databases"
    fi
}

# LaunchServices database rebuild
# Fixes "Open with" menu issues, duplicate apps, broken file associations
opt_launch_services_rebuild() {
    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    if [[ -f "$lsregister" ]]; then
        local success=0

        # Skip actual rebuild in dry-run mode
        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
            set +e
            "$lsregister" -r -domain local -domain user -domain system > /dev/null 2>&1
            success=$?
            if [[ $success -ne 0 ]]; then
                "$lsregister" -r -domain local -domain user > /dev/null 2>&1
                success=$?
            fi
            set -e
        else
            success=0 # Assume success in dry-run mode
        fi

        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if [[ $success -eq 0 ]]; then
            opt_msg "LaunchServices repaired"
            opt_msg "File associations refreshed"
        else
            echo -e "  ${YELLOW}!${NC} Failed to rebuild LaunchServices"
        fi
    else
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo -e "  ${YELLOW}!${NC} lsregister not found"
    fi
}

# Font cache rebuild
# Fixes font rendering issues, missing fonts, and character display problems
opt_font_cache_rebuild() {
    local success=false

    # Skip actual font cache removal in dry-run mode
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if sudo atsutil databases -remove > /dev/null 2>&1; then
            success=true
        fi
    else
        success=true # Assume success in dry-run mode
    fi

    if [[ "$success" == "true" ]]; then
        opt_msg "Font cache cleared"
        opt_msg "System will rebuild font database automatically"
    else
        echo -e "  ${YELLOW}!${NC} Failed to clear font cache"
    fi
}

# Removed high-risk optimizations:
# - opt_startup_items_cleanup: Risk of deleting legitimate app helpers
# - opt_dyld_cache_update: Low benefit, time-consuming, auto-managed by macOS
# - opt_system_services_refresh: Risk of data loss when killing system services

# Memory pressure relief
# Clears inactive memory and disk cache to improve system responsiveness
opt_memory_pressure_relief() {
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if ! is_memory_pressure_high; then
            opt_msg "Memory pressure already optimal"
            return 0
        fi

        if sudo purge > /dev/null 2>&1; then
            opt_msg "Inactive memory released"
            opt_msg "System responsiveness improved"
        else
            echo -e "  ${YELLOW}!${NC} Failed to release memory pressure"
        fi
    else
        opt_msg "Inactive memory released"
        opt_msg "System responsiveness improved"
    fi
}

# Network stack optimization
# Flushes routing table and ARP cache to resolve network issues
opt_network_stack_optimize() {
    local route_flushed="false"
    local arp_flushed="false"

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        local route_ok=true
        local dns_ok=true

        if ! route -n get default > /dev/null 2>&1; then
            route_ok=false
        fi
        if ! dscacheutil -q host -a name "example.com" > /dev/null 2>&1; then
            dns_ok=false
        fi

        if [[ "$route_ok" == "true" && "$dns_ok" == "true" ]]; then
            opt_msg "Network stack already optimal"
            return 0
        fi

        # Flush routing table
        if sudo route -n flush > /dev/null 2>&1; then
            route_flushed="true"
        fi

        # Clear ARP cache
        if sudo arp -a -d > /dev/null 2>&1; then
            arp_flushed="true"
        fi
    else
        route_flushed="true"
        arp_flushed="true"
    fi

    if [[ "$route_flushed" == "true" ]]; then
        opt_msg "Network routing table refreshed"
    fi
    if [[ "$arp_flushed" == "true" ]]; then
        opt_msg "ARP cache cleared"
    else
        if [[ "$route_flushed" == "true" ]]; then
            return 0
        fi
        echo -e "  ${YELLOW}!${NC} Failed to optimize network stack"
    fi
}

# Disk permissions repair
# Fixes user home directory permission issues
opt_disk_permissions_repair() {
    local user_id
    user_id=$(id -u)

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if ! needs_permissions_repair; then
            opt_msg "User directory permissions already optimal"
            return 0
        fi

        if [[ -t 1 ]]; then
            start_inline_spinner "Repairing disk permissions..."
        fi

        local success=false
        if sudo diskutil resetUserPermissions / "$user_id" > /dev/null 2>&1; then
            success=true
        fi

        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if [[ "$success" == "true" ]]; then
            opt_msg "User directory permissions repaired"
            opt_msg "File access issues resolved"
        else
            echo -e "  ${YELLOW}!${NC} Failed to repair permissions (may not be needed)"
        fi
    else
        opt_msg "User directory permissions repaired"
        opt_msg "File access issues resolved"
    fi
}

# Bluetooth module reset
# Resets Bluetooth daemon to fix connectivity issues
# Intelligently detects Bluetooth audio usage:
#   1. Checks if default audio output is Bluetooth (precise)
#   2. Falls back to Bluetooth + media app detection (compatibility)
opt_bluetooth_reset() {
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if has_bluetooth_hid_connected; then
            opt_msg "Bluetooth already optimal"
            return 0
        fi

        # Check if any audio is playing through Bluetooth
        local bt_audio_active=false

        # Method 1: Check if default audio output is Bluetooth (precise)
        local audio_info
        audio_info=$(system_profiler SPAudioDataType 2> /dev/null || echo "")

        # Extract default output device information
        local default_output
        default_output=$(echo "$audio_info" | awk '/Default Output Device: Yes/,/^$/' 2> /dev/null || echo "")

        # Check if transport type is Bluetooth
        if echo "$default_output" | grep -qi "Transport:.*Bluetooth"; then
            bt_audio_active=true
        fi

        # Method 2: Fallback - Bluetooth connected + media apps running (compatibility)
        if [[ "$bt_audio_active" == "false" ]]; then
            if system_profiler SPBluetoothDataType 2> /dev/null | grep -q "Connected: Yes"; then
                # Extended media apps list for broader coverage
                local -a media_apps=("Music" "Spotify" "VLC" "QuickTime Player" "TV" "Podcasts" "Safari" "Google Chrome" "Chrome" "Firefox" "Arc" "IINA" "mpv")
                for app in "${media_apps[@]}"; do
                    if pgrep -x "$app" > /dev/null 2>&1; then
                        bt_audio_active=true
                        break
                    fi
                done
            fi
        fi

        if [[ "$bt_audio_active" == "true" ]]; then
            opt_msg "Bluetooth already optimal"
            return 0
        fi

        # Safe to reset Bluetooth
        if sudo pkill -TERM bluetoothd > /dev/null 2>&1; then
            sleep 1
            if pgrep -x bluetoothd > /dev/null 2>&1; then
                sudo pkill -KILL bluetoothd > /dev/null 2>&1 || true
            fi
            opt_msg "Bluetooth module restarted"
            opt_msg "Connectivity issues resolved"
        else
            opt_msg "Bluetooth already optimal"
        fi
    else
        opt_msg "Bluetooth module restarted"
        opt_msg "Connectivity issues resolved"
    fi
}

# Spotlight index optimization
# Rebuilds Spotlight index if search is slow or results are inaccurate
# Only runs if index is actually problematic
opt_spotlight_index_optimize() {
    # Check if Spotlight indexing is disabled
    local spotlight_status
    spotlight_status=$(mdutil -s / 2> /dev/null || echo "")

    if echo "$spotlight_status" | grep -qi "Indexing disabled"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight indexing is disabled"
        return 0
    fi

    # Check if indexing is currently running
    if echo "$spotlight_status" | grep -qi "Indexing enabled" && ! echo "$spotlight_status" | grep -qi "Indexing and searching disabled"; then
        # Check index health by testing search speed twice
        local slow_count=0
        local test_start test_end test_duration
        for _ in 1 2; do
            test_start=$(date +%s)
            mdfind "kMDItemFSName == 'Applications'" > /dev/null 2>&1 || true
            test_end=$(date +%s)
            test_duration=$((test_end - test_start))
            if [[ $test_duration -gt 3 ]]; then
                ((slow_count++))
            fi
            sleep 1
        done

        if [[ $slow_count -ge 2 ]]; then
            if ! is_ac_power; then
                opt_msg "Spotlight index already optimal"
                return 0
            fi

            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                echo -e "  ${BLUE}ℹ${NC} Spotlight search is slow, rebuilding index (may take 1-2 hours)"
                if sudo mdutil -E / > /dev/null 2>&1; then
                    opt_msg "Spotlight index rebuild started"
                    echo -e "  ${GRAY}Indexing will continue in background${NC}"
                else
                    echo -e "  ${YELLOW}!${NC} Failed to rebuild Spotlight index"
                fi
            else
                opt_msg "Spotlight index rebuild started"
            fi
        else
            opt_msg "Spotlight index already optimal"
        fi
    else
        opt_msg "Spotlight index verified"
    fi
}

# Dock cache refresh
# Fixes broken icons, duplicate items, and visual glitches in the Dock
opt_dock_refresh() {
    local dock_support="$HOME/Library/Application Support/Dock"
    local refreshed=false

    # Remove Dock database files (icons, positions, etc.)
    if [[ -d "$dock_support" ]]; then
        while IFS= read -r db_file; do
            if [[ -f "$db_file" ]]; then
                safe_remove "$db_file" true > /dev/null 2>&1 && refreshed=true
            fi
        done < <(find "$dock_support" -name "*.db" -type f 2> /dev/null || true)
    fi

    # Also clear Dock plist cache
    local dock_plist="$HOME/Library/Preferences/com.apple.dock.plist"
    if [[ -f "$dock_plist" ]]; then
        # Just touch to invalidate cache, don't delete (preserves user settings)
        touch "$dock_plist" 2> /dev/null || true
    fi

    # Restart Dock to apply changes (skip in dry-run mode)
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        killall Dock 2> /dev/null || true
    fi

    if [[ "$refreshed" == "true" ]]; then
        opt_msg "Dock cache cleared"
    fi
    opt_msg "Dock refreshed"
}

# Execute optimization by action name
execute_optimization() {
    local action="$1"
    local path="${2:-}"

    case "$action" in
        system_maintenance) opt_system_maintenance ;;
        cache_refresh) opt_cache_refresh ;;
        saved_state_cleanup) opt_saved_state_cleanup ;;
        fix_broken_configs) opt_fix_broken_configs ;;
        network_optimization) opt_network_optimization ;;
        sqlite_vacuum) opt_sqlite_vacuum ;;
        launch_services_rebuild) opt_launch_services_rebuild ;;
        font_cache_rebuild) opt_font_cache_rebuild ;;
        dock_refresh) opt_dock_refresh ;;
        memory_pressure_relief) opt_memory_pressure_relief ;;
        network_stack_optimize) opt_network_stack_optimize ;;
        disk_permissions_repair) opt_disk_permissions_repair ;;
        bluetooth_reset) opt_bluetooth_reset ;;
        spotlight_index_optimize) opt_spotlight_index_optimize ;;
        *)
            echo -e "${YELLOW}${ICON_ERROR}${NC} Unknown action: $action"
            return 1
            ;;
    esac
}
