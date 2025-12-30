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

# Helper function to get appropriate icon and color for dry-run mode
opt_msg() {
    local message="$1"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $message"
    else
        echo -e "  ${GREEN}✓${NC} $message"
    fi
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
        echo -e "  ${GRAY}-${NC} sqlite3 not available, skipping database optimization"
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

    local -a db_paths=(
        "$HOME/Library/Mail/V*/MailData/Envelope Index*"
        "$HOME/Library/Messages/chat.db"
        "$HOME/Library/Safari/History.db"
        "$HOME/Library/Safari/TopSites.db"
    )

    local vacuumed=0
    local timed_out=0
    local failed=0

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

    if [[ $vacuumed -gt 0 ]]; then
        opt_msg "Optimized $vacuumed databases for Mail, Safari, Messages"
    elif [[ $timed_out -eq 0 && $failed -eq 0 ]]; then
        opt_msg "All databases already optimized"
    else
        echo -e "  ${YELLOW}!${NC} Database optimization incomplete"
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
            success=0  # Assume success in dry-run mode
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
        success=true  # Assume success in dry-run mode
    fi

    if [[ "$success" == "true" ]]; then
        opt_msg "Font cache cleared"
        opt_msg "System will rebuild font database automatically"
    else
        echo -e "  ${YELLOW}!${NC} Failed to clear font cache"
    fi
}

# Startup items cleanup
# Removes broken LaunchAgents and analyzes startup performance impact
opt_startup_items_cleanup() {
    # Check whitelist (respects 'Login items check' setting)
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_login_items"; then
        return 0
    fi

    local -a scan_dirs=(
        "$HOME/Library/LaunchAgents"
        "$HOME/Library/LaunchDaemons"
        "/Library/LaunchAgents"
        "/Library/LaunchDaemons"
    )

    local broken_count=0
    local total_count=0
    local processed_files=0

    for dir in "${scan_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue

        # Check if we need sudo for this directory
        local need_sudo=false
        if [[ "$dir" == "/Library"* ]]; then
            need_sudo=true
        fi

        # Process plists
        local find_cmd=(find)
        if [[ "$need_sudo" == "true" ]]; then
            find_cmd=(sudo find)
        fi

        while IFS= read -r plist_file; do
            # Verify file exists (unless in test mode)
            if [[ -z "${MO_TEST_MODE:-}" && ! -f "$plist_file" ]]; then
                continue
            fi
            ((total_count++))

            # Skip system items (com.apple.*)
            local filename=$(basename "$plist_file")
            [[ "$filename" == com.apple.* ]] && continue

            # Check if plist is valid (use sudo for system dirs)
            local lint_output=""
            local lint_status=0
            local errexit_was_set=0
            [[ $- == *e* ]] && errexit_was_set=1
            set +e
            if [[ "$need_sudo" == "true" ]]; then
                lint_output=$(sudo plutil -lint "$plist_file" 2>&1)
                lint_status=$?
            else
                lint_output=$(plutil -lint "$plist_file" 2>&1)
                lint_status=$?
            fi
            if [[ $errexit_was_set -eq 1 ]]; then
                set -e
            fi

            if [[ $lint_status -ne 0 ]]; then
                # Skip if lint failed due to permissions or transient read errors
                if echo "$lint_output" | grep -qi "permission\\|operation not permitted\\|not permitted"; then
                    continue
                fi

                # Invalid plist - remove it
                if command -v should_protect_path > /dev/null && should_protect_path "$plist_file"; then
                    continue
                fi

                if [[ "$need_sudo" == "true" ]]; then
                    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                        sudo launchctl unload "$plist_file" 2> /dev/null || true
                    fi
                    if safe_sudo_remove "$plist_file"; then
                        ((broken_count++))
                    else
                        echo -e "  ${YELLOW}!${NC} Failed to remove (sudo) $plist_file"
                    fi
                else
                    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                        launchctl unload "$plist_file" 2> /dev/null || true
                    fi
                    if safe_remove "$plist_file" true; then
                        ((broken_count++))
                    else
                        echo -e "  ${YELLOW}!${NC} Failed to remove $plist_file"
                    fi
                fi
                continue
            fi

            # Extract program path
            local program=""
            program=$(plutil -extract Program raw "$plist_file" 2> /dev/null || echo "")

            if [[ -z "$program" ]]; then
                program=$(plutil -extract ProgramArguments.0 raw "$plist_file" 2> /dev/null || echo "")
            fi

            program="${program/#\~/$HOME}"

            # Skip paths with variables or non-absolute program definitions
            if [[ "$program" == *'$'* || "$program" != /* ]]; then
                continue
            fi
            # Check for orphaned privileged helpers (app uninstalled but helper remains)
            local associated_bundle=""
            associated_bundle=$(plutil -extract AssociatedBundleIdentifiers.0 raw "$plist_file" 2> /dev/null || echo "")

            if [[ -n "$associated_bundle" ]]; then
                # Check if the associated app exists
                local app_path=""
                # First check standard locations
                if [[ -d "/Applications/$associated_bundle.app" ]]; then
                    app_path="/Applications/$associated_bundle.app"
                elif [[ -d "$HOME/Applications/$associated_bundle.app" ]]; then
                    app_path="$HOME/Applications/$associated_bundle.app"
                else
                    # Try extracting app name from bundle ID (e.g., com.dropbox.Dropbox -> Dropbox)
                    local app_name="${associated_bundle##*.}"
                    if [[ -n "$app_name" && -d "/Applications/$app_name.app" ]]; then
                        app_path="/Applications/$app_name.app"
                    elif [[ -n "$app_name" && -d "$HOME/Applications/$app_name.app" ]]; then
                        app_path="$HOME/Applications/$app_name.app"
                    else
                        # Fallback to mdfind (slower but comprehensive, with 10s timeout)
                        app_path=$(run_with_timeout 10 mdfind "kMDItemCFBundleIdentifier == '$associated_bundle'" 2> /dev/null | head -1 || echo "")
                    fi
                fi

                # CRITICAL FIX: Only consider it orphaned if BOTH conditions are true:
                # 1. Associated app is not found
                # 2. The program/executable itself also doesn't exist
                if [[ -z "$app_path" ]]; then
                    if command -v should_protect_path > /dev/null && should_protect_path "$plist_file"; then
                        continue
                    fi

                    # CRITICAL: Check if the program itself exists (reuse already extracted program path)
                    # If the executable exists, this is NOT an orphan - it's a valid helper
                    # whose app we just can't find (maybe mdfind indexing issue, non-standard location, etc.)
                    if [[ -n "$program" && -e "$program" ]]; then
                        debug_log "Keeping LaunchAgent (program exists): $plist_file -> $program"
                        continue
                    fi

                    # Double check we are not deleting system files
                    if [[ "$program" == /System/* ||
                        "$program" == /usr/lib/* ||
                        "$program" == /usr/bin/* ||
                        "$program" == /usr/sbin/* ||
                        "$program" == /Library/Apple/* ]]; then
                        continue
                    fi

                    # Only delete if BOTH app and program are missing
                    debug_log "Removing orphaned helper (app not found, program missing): $plist_file"

                    if [[ "$need_sudo" == "true" ]]; then
                        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                            sudo launchctl unload "$plist_file" 2> /dev/null || true
                        fi
                        # remove the plist
                        safe_sudo_remove "$plist_file"

                        # The program doesn't exist (verified above), so no need to remove it
                        ((broken_count++))
                        opt_msg "Removed orphaned helper: $(basename "$plist_file" .plist)"
                    else
                        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                            launchctl unload "$plist_file" 2> /dev/null || true
                        fi
                        safe_remove "$plist_file" true
                        ((broken_count++))
                        opt_msg "Removed orphaned helper: $(basename "$plist_file" .plist)"
                    fi
                    continue
                fi
            fi

            # If program doesn't exist, remove the launch agent/daemon
            if [[ -n "$program" && ! -e "$program" ]]; then
                if command -v should_protect_path > /dev/null && should_protect_path "$plist_file"; then
                    continue
                fi

                if [[ "$need_sudo" == "true" ]]; then
                    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                        sudo launchctl unload "$plist_file" 2> /dev/null || true
                    fi
                    if safe_sudo_remove "$plist_file"; then
                        ((broken_count++))
                    else
                        echo -e "  ${YELLOW}!${NC} Failed to remove (sudo) $plist_file"
                    fi
                else
                    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                        launchctl unload "$plist_file" 2> /dev/null || true
                    fi
                    if safe_remove "$plist_file" true; then
                        ((broken_count++))
                    else
                        echo -e "  ${YELLOW}!${NC} Failed to remove $plist_file"
                    fi
                fi
            fi
        done < <("${find_cmd[@]}" "$dir" -maxdepth 1 -name "*.plist" -type f 2> /dev/null || true)
    done

    if [[ $broken_count -gt 0 ]]; then
        opt_msg "Removed $broken_count broken startup items"
    fi

    if [[ $total_count -gt 0 ]]; then
        opt_msg "Verified $total_count startup items"
    else
        opt_msg "No startup items found"
    fi
}

# dyld shared cache update
# Rebuilds dynamic linker shared cache to improve app launch speed
# Only beneficial after new app installations or system updates
opt_dyld_cache_update() {
    # Check if command exists
    if ! command -v update_dyld_shared_cache > /dev/null 2>&1; then
        echo -e "  ${GRAY}-${NC} dyld cache (automatically managed by macOS)"
        return 0
    fi

    # Skip if dyld cache was already rebuilt recently (within 24 hours)
    local dyld_cache_path="/var/db/dyld/dyld_shared_cache_$(uname -m)"
    if [[ -e "$dyld_cache_path" ]]; then
        local cache_mtime
        cache_mtime=$(stat -f "%m" "$dyld_cache_path" 2> /dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local time_diff=$((current_time - cache_mtime))
        local one_day_seconds=$((24 * 3600))

        if [[ $time_diff -lt $one_day_seconds ]]; then
            opt_msg "dyld shared cache already up-to-date"
            return 0
        fi
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "Rebuilding dyld cache..."
    fi

    local success=false
    local exit_code=0

    # Skip actual rebuild in dry-run mode
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        # This can take 1-2 minutes on some systems (180 second timeout)
        set +e
        run_with_timeout 180 sudo update_dyld_shared_cache -force > /dev/null 2>&1
        exit_code=$?
        set -e
        if [[ $exit_code -eq 0 ]]; then
            success=true
        fi
    else
        success=true  # Assume success in dry-run mode
        exit_code=0
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ "$success" == "true" ]]; then
        opt_msg "dyld shared cache rebuilt"
        opt_msg "App launch speed improved"
    elif [[ $exit_code -eq 124 ]]; then
        echo -e "  ${YELLOW}!${NC} dyld cache update timed out"
    else
        echo -e "  ${GRAY}-${NC} dyld cache update skipped (automatically managed)"
    fi
}

# System services refresh
# Restarts system services to apply cache and configuration changes
opt_system_services_refresh() {
    local -a services=(
        "cfprefsd:Preferences"
        "lsd:LaunchServices"
        "iconservicesagent:Icon Services"
        "fontd:Font Server"
    )
    local -a restarted_services=()

    # Skip actual service restarts in dry-run mode
    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        for service_entry in "${services[@]}"; do
            IFS=':' read -r process_name display_name <<< "$service_entry"

            # Special handling for cfprefsd (use -HUP instead of normal kill)
            if [[ "$process_name" == "cfprefsd" ]]; then
                if killall -HUP "$process_name" 2> /dev/null; then
                    restarted_services+=("$display_name")
                fi
            else
                if killall "$process_name" 2> /dev/null; then
                    restarted_services+=("$display_name")
                fi
            fi
        done
    else
        # In dry-run mode, show all services that would be restarted
        for service_entry in "${services[@]}"; do
            IFS=':' read -r _ display_name <<< "$service_entry"
            restarted_services+=("$display_name")
        done
    fi

    if [[ ${#restarted_services[@]} -gt 0 ]]; then
        opt_msg "Refreshed ${#restarted_services[@]} system services"
        for service in "${restarted_services[@]}"; do
            echo -e "    • $service"
        done
    else
        opt_msg "System services already optimal"
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
        startup_items_cleanup) opt_startup_items_cleanup ;;
        dyld_cache_update) opt_dyld_cache_update ;;
        system_services_refresh) opt_system_services_refresh ;;
        dock_refresh) opt_dock_refresh ;;
        *)
            echo -e "${YELLOW}${ICON_ERROR}${NC} Unknown action: $action"
            return 1
            ;;
    esac
}
