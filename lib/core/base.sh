#!/bin/bash
# Mole - Base Definitions and Utilities
# Core definitions, constants, and basic utility functions used by all modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_BASE_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_BASE_LOADED=1

# ============================================================================
# Color Definitions
# ============================================================================
readonly ESC=$'\033'
readonly GREEN="${ESC}[0;32m"
readonly BLUE="${ESC}[0;34m"
readonly CYAN="${ESC}[0;36m"
readonly YELLOW="${ESC}[0;33m"
readonly PURPLE="${ESC}[0;35m"
readonly PURPLE_BOLD="${ESC}[1;35m"
readonly RED="${ESC}[0;31m"
readonly GRAY="${ESC}[0;90m"
readonly NC="${ESC}[0m"

# ============================================================================
# Icon Definitions
# ============================================================================
readonly ICON_CONFIRM="◎"
readonly ICON_ADMIN="⚙"
readonly ICON_SUCCESS="✓"
readonly ICON_ERROR="☻"
readonly ICON_EMPTY="○"
readonly ICON_SOLID="●"
readonly ICON_LIST="•"
readonly ICON_ARROW="➤"
readonly ICON_WARNING="☻"
readonly ICON_NAV_UP="↑"
readonly ICON_NAV_DOWN="↓"
readonly ICON_NAV_LEFT="←"
readonly ICON_NAV_RIGHT="→"

# ============================================================================
# Global Configuration Constants
# ============================================================================
readonly MOLE_TEMP_FILE_AGE_DAYS=7       # Temp file cleanup threshold
readonly MOLE_ORPHAN_AGE_DAYS=60         # Orphaned data threshold
readonly MOLE_MAX_PARALLEL_JOBS=15       # Parallel job limit
readonly MOLE_MAIL_DOWNLOADS_MIN_KB=5120 # Mail attachments size threshold
readonly MOLE_LOG_AGE_DAYS=7             # System log retention
readonly MOLE_CRASH_REPORT_AGE_DAYS=7    # Crash report retention
readonly MOLE_SAVED_STATE_AGE_DAYS=7     # App saved state retention
readonly MOLE_TM_BACKUP_SAFE_HOURS=48    # Time Machine failed backup safety window

# ============================================================================
# Seasonal Functions
# ============================================================================
is_christmas_season() {
    local month day
    month=$(date +%-m)
    day=$(date +%-d)

    # December 10 to December 31
    if [[ $month -eq 12 && $day -ge 10 && $day -le 31 ]]; then
        return 0
    fi
    return 1
}

# ============================================================================
# Whitelist Configuration
# ============================================================================
readonly FINDER_METADATA_SENTINEL="FINDER_METADATA"
declare -a DEFAULT_WHITELIST_PATTERNS=(
    "$HOME/Library/Caches/ms-playwright*"
    "$HOME/.cache/huggingface*"
    "$HOME/.m2/repository/*"
    "$HOME/.ollama/models/*"
    "$HOME/Library/Caches/com.nssurge.surge-mac/*"
    "$HOME/Library/Application Support/com.nssurge.surge-mac/*"
    "$HOME/Library/Caches/org.R-project.R/R/renv/*"
    "$HOME/Library/Caches/JetBrains*"
    "$HOME/Library/Caches/com.jetbrains.toolbox*"
    "$HOME/Library/Caches/com.apple.finder"
    "$FINDER_METADATA_SENTINEL"
)

declare -a DEFAULT_OPTIMIZE_WHITELIST_PATTERNS=(
    "check_brew_updates"
    "check_brew_health"
    "check_touchid"
    "check_git_config"
)

# ============================================================================
# BSD Stat Compatibility
# ============================================================================
readonly STAT_BSD="/usr/bin/stat"

# Get file size in bytes using BSD stat
get_file_size() {
    local file="$1"
    local result
    result=$($STAT_BSD -f%z "$file" 2> /dev/null)
    echo "${result:-0}"
}

# Get file modification time using BSD stat
# Returns: epoch seconds
get_file_mtime() {
    local file="$1"
    [[ -z "$file" ]] && {
        echo "0"
        return
    }
    local result
    result=$($STAT_BSD -f%m "$file" 2> /dev/null)
    echo "${result:-0}"
}

# Get file owner username using BSD stat
get_file_owner() {
    local file="$1"
    $STAT_BSD -f%Su "$file" 2> /dev/null || echo ""
}

# ============================================================================
# System Utilities
# ============================================================================

# Check if System Integrity Protection is enabled
# Returns: 0 if SIP is enabled, 1 if disabled or cannot determine
is_sip_enabled() {
    if ! command -v csrutil > /dev/null 2>&1; then
        return 0
    fi

    local sip_status
    sip_status=$(csrutil status 2> /dev/null || echo "")

    if echo "$sip_status" | grep -qi "enabled"; then
        return 0
    else
        return 1
    fi
}

# Check if running in interactive terminal
# Returns: 0 if interactive, 1 otherwise
is_interactive() {
    [[ -t 1 ]]
}

# Detect CPU architecture
# Returns: "Apple Silicon" or "Intel"
detect_architecture() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "Apple Silicon"
    else
        echo "Intel"
    fi
}

# Get free disk space on root volume
# Returns: human-readable string (e.g., "100G")
get_free_space() {
    command df -h / | awk 'NR==2 {print $4}'
}

# Get optimal number of parallel jobs for a given operation type
# Args: $1 - operation type (scan|io|compute|default)
# Returns: number of jobs
get_optimal_parallel_jobs() {
    local operation_type="${1:-default}"
    local cpu_cores
    cpu_cores=$(sysctl -n hw.ncpu 2> /dev/null || echo 4)
    case "$operation_type" in
        scan | io)
            echo $((cpu_cores * 2))
            ;;
        compute)
            echo "$cpu_cores"
            ;;
        *)
            echo $((cpu_cores + 2))
            ;;
    esac
}

# ============================================================================
# Formatting Utilities
# ============================================================================

# Convert bytes to human-readable format
# Args: $1 - size in bytes
# Returns: formatted string (e.g., "1.50GB", "256MB", "4KB")
bytes_to_human() {
    local bytes="$1"
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return 1
    fi

    if ((bytes >= 1073741824)); then # >= 1GB
        local divisor=1073741824
        local whole=$((bytes / divisor))
        local remainder=$((bytes % divisor))
        local frac=$(((remainder * 100 + divisor / 2) / divisor))
        if ((frac >= 100)); then
            frac=0
            ((whole++))
        fi
        printf "%d.%02dGB\n" "$whole" "$frac"
        return 0
    fi

    if ((bytes >= 1048576)); then # >= 1MB
        local divisor=1048576
        local whole=$((bytes / divisor))
        local remainder=$((bytes % divisor))
        local frac=$(((remainder * 10 + divisor / 2) / divisor))
        if ((frac >= 10)); then
            frac=0
            ((whole++))
        fi
        printf "%d.%01dMB\n" "$whole" "$frac"
        return 0
    fi

    if ((bytes >= 1024)); then
        local rounded_kb=$(((bytes + 512) / 1024))
        printf "%dKB\n" "$rounded_kb"
        return 0
    fi

    printf "%dB\n" "$bytes"
}

# Convert kilobytes to human-readable format
# Args: $1 - size in KB
# Returns: formatted string
bytes_to_human_kb() {
    bytes_to_human "$((${1:-0} * 1024))"
}

# Get brand-friendly name for an application
# Args: $1 - application name
# Returns: branded name if mapping exists, original name otherwise
get_brand_name() {
    local name="$1"

    case "$name" in
        "qiyimac" | "爱奇艺") echo "iQiyi" ;;
        "wechat" | "微信") echo "WeChat" ;;
        "QQ") echo "QQ" ;;
        "VooV Meeting" | "腾讯会议") echo "VooV Meeting" ;;
        "dingtalk" | "钉钉") echo "DingTalk" ;;
        "NeteaseMusic" | "网易云音乐") echo "NetEase Music" ;;
        "BaiduNetdisk" | "百度网盘") echo "Baidu NetDisk" ;;
        "alipay" | "支付宝") echo "Alipay" ;;
        "taobao" | "淘宝") echo "Taobao" ;;
        "futunn" | "富途牛牛") echo "Futu NiuNiu" ;;
        "tencent lemon" | "Tencent Lemon Cleaner") echo "Tencent Lemon" ;;
        "keynote" | "Keynote") echo "Keynote" ;;
        "pages" | "Pages") echo "Pages" ;;
        "numbers" | "Numbers") echo "Numbers" ;;
        *) echo "$name" ;;
    esac
}

# ============================================================================
# Temporary File Management
# ============================================================================

# Tracked temporary files and directories
declare -a MOLE_TEMP_FILES=()
declare -a MOLE_TEMP_DIRS=()

# Create tracked temporary file
# Returns: temp file path
create_temp_file() {
    local temp
    temp=$(mktemp) || return 1
    MOLE_TEMP_FILES+=("$temp")
    echo "$temp"
}

# Create tracked temporary directory
# Returns: temp directory path
create_temp_dir() {
    local temp
    temp=$(mktemp -d) || return 1
    MOLE_TEMP_DIRS+=("$temp")
    echo "$temp"
}

# Register existing file for cleanup
register_temp_file() {
    MOLE_TEMP_FILES+=("$1")
}

# Register existing directory for cleanup
register_temp_dir() {
    MOLE_TEMP_DIRS+=("$1")
}

# Create temp file with prefix (for analyze.sh compatibility)
# Compatible with both BSD mktemp (macOS default) and GNU mktemp (coreutils)
mktemp_file() {
    local prefix="${1:-mole}"
    # Use TMPDIR if set, otherwise /tmp
    # Add .XXXXXX suffix to work with both BSD and GNU mktemp
    mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Cleanup all tracked temp files and directories
cleanup_temp_files() {
    local file
    if [[ ${#MOLE_TEMP_FILES[@]} -gt 0 ]]; then
        for file in "${MOLE_TEMP_FILES[@]}"; do
            [[ -f "$file" ]] && rm -f "$file" 2> /dev/null || true
        done
    fi

    if [[ ${#MOLE_TEMP_DIRS[@]} -gt 0 ]]; then
        for file in "${MOLE_TEMP_DIRS[@]}"; do
            [[ -d "$file" ]] && rm -rf "$file" 2> /dev/null || true # SAFE: cleanup_temp_files
        done
    fi

    MOLE_TEMP_FILES=()
    MOLE_TEMP_DIRS=()
}

# ============================================================================
# Section Tracking (for progress indication)
# ============================================================================

# Global section tracking variables
TRACK_SECTION=0
SECTION_ACTIVITY=0

# Start a new section
# Args: $1 - section title
start_section() {
    TRACK_SECTION=1
    SECTION_ACTIVITY=0
    echo ""
    echo -e "${PURPLE_BOLD}${ICON_ARROW} $1${NC}"
}

# End a section
# Shows "Nothing to tidy" if no activity was recorded
end_section() {
    if [[ $TRACK_SECTION -eq 1 && $SECTION_ACTIVITY -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Nothing to tidy"
    fi
    TRACK_SECTION=0
}

# Mark activity in current section
note_activity() {
    if [[ $TRACK_SECTION -eq 1 ]]; then
        SECTION_ACTIVITY=1
    fi
}
