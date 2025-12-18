#!/bin/bash
# Mole - Application Protection
# System critical and data-protected application lists

set -euo pipefail

if [[ -n "${MOLE_APP_PROTECTION_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_APP_PROTECTION_LOADED=1

_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_CORE_DIR/base.sh"

# ============================================================================
# App Management Functions
# ============================================================================

# System critical components that should NEVER be uninstalled
readonly SYSTEM_CRITICAL_BUNDLES=(
    "com.apple.*" # System essentials
    "loginwindow"
    "dock"
    "systempreferences"
    "finder"
    "safari"
    "com.apple.Settings*"
    "com.apple.SystemSettings*"
    "com.apple.controlcenter*"
    "com.apple.backgroundtaskmanagement*"
    "com.apple.loginitems*"
    "com.apple.sharedfilelist*"
    "com.apple.sfl*"
    "backgroundtaskmanagementagent"
    "keychain*"
    "security*"
    "bluetooth*"
    "wifi*"
    "network*"
    "tcc"
    "notification*"
    "accessibility*"
    "universalaccess*"
    "HIToolbox*"
    "textinput*"
    "TextInput*"
    "keyboard*"
    "Keyboard*"
    "inputsource*"
    "InputSource*"
    "keylayout*"
    "KeyLayout*"
    "GlobalPreferences"
    ".GlobalPreferences"
    # Input methods (critical for international users)
    "com.tencent.inputmethod.QQInput"
    "com.sogou.inputmethod.*"
    "com.baidu.inputmethod.*"
    "com.apple.inputmethod.*"
    "com.googlecode.rimeime.*"
    "im.rime.*"
    "org.pqrs.Karabiner*"
    "*.inputmethod"
    "*.InputMethod"
    "*IME"
    "com.apple.inputsource*"
    "com.apple.TextInputMenuAgent"
    "com.apple.TextInputSwitcher"
)

# Apps with important data/licenses - protect during cleanup but allow uninstall
readonly DATA_PROTECTED_BUNDLES=(
    # ============================================================================
    # System Utilities & Cleanup Tools
    # ============================================================================
    "com.nektony.*"                 # App Cleaner & Uninstaller
    "com.macpaw.*"                  # CleanMyMac, CleanMaster
    "com.freemacsoft.AppCleaner"    # AppCleaner
    "com.omnigroup.omnidisksweeper" # OmniDiskSweeper
    "com.daisydiskapp.*"            # DaisyDisk
    "com.tunabellysoftware.*"       # Disk Utility apps
    "com.grandperspectiv.*"         # GrandPerspective
    "com.binaryfruit.*"             # FusionCast

    # ============================================================================
    # Password Managers & Security
    # ============================================================================
    "com.1password.*" # 1Password
    "com.agilebits.*" # 1Password legacy
    "com.lastpass.*"  # LastPass
    "com.dashlane.*"  # Dashlane
    "com.bitwarden.*" # Bitwarden
    "com.keepassx.*"  # KeePassXC
    "org.keepassx.*"  # KeePassX
    "com.authy.*"     # Authy
    "com.yubico.*"    # YubiKey Manager

    # ============================================================================
    # Development Tools - IDEs & Editors
    # ============================================================================
    "com.jetbrains.*"              # JetBrains IDEs (IntelliJ, DataGrip, etc.)
    "JetBrains*"                   # JetBrains Application Support folders
    "com.microsoft.VSCode"         # Visual Studio Code
    "com.visualstudio.code.*"      # VS Code variants
    "com.sublimetext.*"            # Sublime Text
    "com.sublimehq.*"              # Sublime Merge
    "com.microsoft.VSCodeInsiders" # VS Code Insiders
    "com.apple.dt.Xcode"           # Xcode (keep settings)
    "com.coteditor.CotEditor"      # CotEditor
    "com.macromates.TextMate"      # TextMate
    "com.panic.Nova"               # Nova
    "abnerworks.Typora"            # Typora (Markdown editor)
    "com.uranusjr.macdown"         # MacDown

    # ============================================================================
    # AI & LLM Tools
    # ============================================================================
    "com.todesktop.*"             # Cursor (often uses generic todesktop ID)
    "Cursor"                      # Cursor App Support
    "com.anthropic.claude*"       # Claude
    "Claude"                      # Claude App Support
    "com.openai.chat*"            # ChatGPT
    "ChatGPT"                     # ChatGPT App Support
    "com.ollama.ollama"           # Ollama
    "Ollama"                      # Ollama App Support
    "com.lmstudio.lmstudio"       # LM Studio
    "LM Studio"                   # LM Studio App Support
    "co.supertool.chatbox"        # Chatbox
    "page.jan.jan"                # Jan
    "com.huggingface.huggingchat" # HuggingChat
    "Gemini"                      # Gemini
    "com.perplexity.Perplexity"   # Perplexity
    "com.drawthings.DrawThings"   # Draw Things
    "com.divamgupta.diffusionbee" # DiffusionBee
    "com.exafunction.windsurf"    # Windsurf
    "com.quora.poe.electron"      # Poe
    "chat.openai.com.*"           # OpenAI web wrappers

    # ============================================================================
    # Development Tools - Database Clients
    # ============================================================================
    "com.sequelpro.*"                   # Sequel Pro
    "com.sequel-ace.*"                  # Sequel Ace
    "com.tinyapp.*"                     # TablePlus
    "com.dbeaver.*"                     # DBeaver
    "com.navicat.*"                     # Navicat
    "com.mongodb.compass"               # MongoDB Compass
    "com.redis.RedisInsight"            # Redis Insight
    "com.pgadmin.pgadmin4"              # pgAdmin
    "com.eggerapps.Sequel-Pro"          # Sequel Pro legacy
    "com.valentina-db.Valentina-Studio" # Valentina Studio
    "com.dbvis.DbVisualizer"            # DbVisualizer

    # ============================================================================
    # Development Tools - API & Network
    # ============================================================================
    "com.postmanlabs.mac"      # Postman
    "com.konghq.insomnia"      # Insomnia
    "com.CharlesProxy.*"       # Charles Proxy
    "com.proxyman.*"           # Proxyman
    "com.getpaw.*"             # Paw
    "com.luckymarmot.Paw"      # Paw legacy
    "com.charlesproxy.charles" # Charles
    "com.telerik.Fiddler"      # Fiddler
    "com.usebruno.app"         # Bruno (API client)

    # ============================================================================
    # Network Proxy & VPN Tools (Broad Glob Protection)
    # ============================================================================
    # Clash variants
    "*clash*"               # All Clash variants (ClashX, ClashX Pro, Clash Verge, etc)
    "*Clash*"               # Capitalized variants
    "com.nssurge.surge-mac" # Surge
    "*surge*"               # Surge variants
    "*Surge*"               # Surge variants
    "mihomo*"               # Mihomo Party and variants
    "*openvpn*"             # OpenVPN Connect and variants
    "*OpenVPN*"             # OpenVPN capitalized variants
    "net.openvpn.*"         # OpenVPN bundle IDs

    # Proxy Clients (Shadowsocks, V2Ray, etc)
    "*ShadowsocksX-NG*" # ShadowsocksX-NG
    "com.qiuyuzhou.*"   # ShadowsocksX-NG bundle
    "*v2ray*"           # V2Ray variants
    "*V2Ray*"           # V2Ray variants
    "*v2box*"           # V2Box
    "*V2Box*"           # V2Box
    "*nekoray*"         # Nekoray
    "*sing-box*"        # Sing-box
    "*OneBox*"          # OneBox
    "*hiddify*"         # Hiddify
    "*Hiddify*"         # Hiddify
    "*loon*"            # Loon
    "*Loon*"            # Loon
    "*quantumult*"      # Quantumult X

    # Mesh & Corporate VPNs
    "*tailscale*"       # Tailscale
    "io.tailscale.*"    # Tailscale bundle
    "*zerotier*"        # ZeroTier
    "com.zerotier.*"    # ZeroTier bundle
    "*1dot1dot1dot1*"   # Cloudflare WARP
    "*cloudflare*warp*" # Cloudflare WARP

    # Commercial VPNs
    "*nordvpn*"               # NordVPN
    "*expressvpn*"            # ExpressVPN
    "*protonvpn*"             # ProtonVPN
    "*surfshark*"             # Surfshark
    "*windscribe*"            # Windscribe
    "*mullvad*"               # Mullvad
    "*privateinternetaccess*" # PIA

    # Screensaver & Dynamic Wallpaper
    "*Aerial*" # Aerial screensaver (all case variants)
    "*aerial*" # Aerial lowercase
    "*Fliqlo*" # Fliqlo screensaver (all case variants)
    "*fliqlo*" # Fliqlo lowercase

    # ============================================================================
    # Development Tools - Git & Version Control
    # ============================================================================
    "com.github.GitHubDesktop"       # GitHub Desktop
    "com.sublimemerge"               # Sublime Merge
    "com.torusknot.SourceTreeNotMAS" # SourceTree
    "com.git-tower.Tower*"           # Tower
    "com.gitfox.GitFox"              # GitFox
    "com.github.Gitify"              # Gitify
    "com.fork.Fork"                  # Fork
    "com.axosoft.gitkraken"          # GitKraken

    # ============================================================================
    # Development Tools - Terminal & Shell
    # ============================================================================
    "com.googlecode.iterm2"  # iTerm2
    "net.kovidgoyal.kitty"   # Kitty
    "io.alacritty"           # Alacritty
    "com.github.wez.wezterm" # WezTerm
    "com.hyper.Hyper"        # Hyper
    "com.mizage.divvy"       # Divvy
    "com.fig.Fig"            # Fig (terminal assistant)
    "dev.warp.Warp-Stable"   # Warp
    "com.termius-dmg"        # Termius (SSH client)

    # ============================================================================
    # Development Tools - Docker & Virtualization
    # ============================================================================
    "com.docker.docker"             # Docker Desktop
    "com.getutm.UTM"                # UTM
    "com.vmware.fusion"             # VMware Fusion
    "com.parallels.desktop.*"       # Parallels Desktop
    "org.virtualbox.app.VirtualBox" # VirtualBox
    "com.vagrant.*"                 # Vagrant
    "com.orbstack.OrbStack"         # OrbStack

    # ============================================================================
    # System Monitoring & Performance
    # ============================================================================
    "com.bjango.istatmenus*"       # iStat Menus
    "eu.exelban.Stats"             # Stats
    "com.monitorcontrol.*"         # MonitorControl
    "com.bresink.system-toolkit.*" # TinkerTool System
    "com.mediaatelier.MenuMeters"  # MenuMeters
    "com.activity-indicator.app"   # Activity Indicator
    "net.cindori.sensei"           # Sensei

    # ============================================================================
    # Window Management & Productivity
    # ============================================================================
    "com.macitbetter.*"            # BetterTouchTool, BetterSnapTool
    "com.hegenberg.*"              # BetterTouchTool legacy
    "com.manytricks.*"             # Moom, Witch, Name Mangler, Resolutionator
    "com.divisiblebyzero.*"        # Spectacle
    "com.koingdev.*"               # Koingg apps
    "com.if.Amphetamine"           # Amphetamine
    "com.lwouis.alt-tab-macos"     # AltTab
    "net.matthewpalmer.Vanilla"    # Vanilla
    "com.lightheadsw.Caffeine"     # Caffeine
    "com.contextual.Contexts"      # Contexts
    "com.amethyst.Amethyst"        # Amethyst
    "com.knollsoft.Rectangle"      # Rectangle
    "com.knollsoft.Hookshot"       # Hookshot
    "com.surteesstudios.Bartender" # Bartender
    "com.gaosun.eul"               # eul (system monitor)
    "com.pointum.hazeover"         # HazeOver

    # ============================================================================
    # Launcher & Automation
    # ============================================================================
    "com.runningwithcrayons.Alfred"   # Alfred
    "com.raycast.macos"               # Raycast
    "com.blacktree.Quicksilver"       # Quicksilver
    "com.stairways.keyboardmaestro.*" # Keyboard Maestro
    "com.manytricks.Butler"           # Butler
    "com.happenapps.Quitter"          # Quitter
    "com.pilotmoon.scroll-reverser"   # Scroll Reverser
    "org.pqrs.Karabiner-Elements"     # Karabiner-Elements
    "com.apple.Automator"             # Automator (system, but keep user workflows)

    # ============================================================================
    # Note-Taking & Documentation
    # ============================================================================
    "com.bear-writer.*"           # Bear
    "com.typora.*"                # Typora
    "com.ulyssesapp.*"            # Ulysses
    "com.literatureandlatte.*"    # Scrivener
    "com.dayoneapp.*"             # Day One
    "notion.id"                   # Notion
    "md.obsidian"                 # Obsidian
    "com.logseq.logseq"           # Logseq
    "com.evernote.Evernote"       # Evernote
    "com.onenote.mac"             # OneNote
    "com.omnigroup.OmniOutliner*" # OmniOutliner
    "net.shinyfrog.bear"          # Bear legacy
    "com.goodnotes.GoodNotes"     # GoodNotes
    "com.marginnote.MarginNote*"  # MarginNote
    "com.roamresearch.*"          # Roam Research
    "com.reflect.ReflectApp"      # Reflect
    "com.inkdrop.*"               # Inkdrop

    # ============================================================================
    # Design & Creative Tools
    # ============================================================================
    "com.adobe.*"             # Adobe Creative Suite
    "com.bohemiancoding.*"    # Sketch
    "com.figma.*"             # Figma
    "com.framerx.*"           # Framer
    "com.zeplin.*"            # Zeplin
    "com.invisionapp.*"       # InVision
    "com.principle.*"         # Principle
    "com.pixelmatorteam.*"    # Pixelmator
    "com.affinitydesigner.*"  # Affinity Designer
    "com.affinityphoto.*"     # Affinity Photo
    "com.affinitypublisher.*" # Affinity Publisher
    "com.linearity.curve"     # Linearity Curve
    "com.canva.CanvaDesktop"  # Canva
    "com.maxon.cinema4d"      # Cinema 4D
    "com.autodesk.*"          # Autodesk products
    "com.sketchup.*"          # SketchUp

    # ============================================================================
    # Communication & Collaboration
    # ============================================================================
    "com.tencent.xinWeChat"                   # WeChat (Chinese users)
    "com.tencent.qq"                          # QQ
    "com.alibaba.DingTalkMac"                 # DingTalk
    "com.alibaba.AliLang.osx"                 # AliLang (retain login/config data)
    "com.alibaba.alilang3.osx.ShipIt"         # AliLang updater component
    "com.alibaba.AlilangMgr.QueryNetworkInfo" # AliLang network helper
    "us.zoom.xos"                             # Zoom
    "com.microsoft.teams*"                    # Microsoft Teams
    "com.slack.Slack"                         # Slack
    "com.hnc.Discord"                         # Discord
    "org.telegram.desktop"                    # Telegram
    "ru.keepcoder.Telegram"                   # Telegram legacy
    "net.whatsapp.WhatsApp"                   # WhatsApp
    "com.skype.skype"                         # Skype
    "com.cisco.webexmeetings"                 # Webex
    "com.ringcentral.RingCentral"             # RingCentral
    "com.readdle.smartemail-Mac"              # Spark Email
    "com.airmail.*"                           # Airmail
    "com.postbox-inc.postbox"                 # Postbox
    "com.tinyspeck.slackmacgap"               # Slack legacy

    # ============================================================================
    # Task Management & Productivity
    # ============================================================================
    "com.omnigroup.OmniFocus*" # OmniFocus
    "com.culturedcode.*"       # Things
    "com.todoist.*"            # Todoist
    "com.any.do.*"             # Any.do
    "com.ticktick.*"           # TickTick
    "com.microsoft.to-do"      # Microsoft To Do
    "com.trello.trello"        # Trello
    "com.asana.nativeapp"      # Asana
    "com.clickup.*"            # ClickUp
    "com.monday.desktop"       # Monday.com
    "com.airtable.airtable"    # Airtable
    "com.notion.id"            # Notion (also note-taking)
    "com.linear.linear"        # Linear

    # ============================================================================
    # File Transfer & Sync
    # ============================================================================
    "com.panic.transmit*"            # Transmit (FTP/SFTP)
    "com.binarynights.ForkLift*"     # ForkLift
    "com.noodlesoft.Hazel"           # Hazel
    "com.cyberduck.Cyberduck"        # Cyberduck
    "io.filezilla.FileZilla"         # FileZilla
    "com.apple.Xcode.CloudDocuments" # Xcode Cloud Documents
    "com.synology.*"                 # Synology apps

    # ============================================================================
    # Screenshot & Recording
    # ============================================================================
    "com.cleanshot.*"                   # CleanShot X
    "com.xnipapp.xnip"                  # Xnip
    "com.reincubate.camo"               # Camo
    "com.tunabellysoftware.ScreenFloat" # ScreenFloat
    "net.telestream.screenflow*"        # ScreenFlow
    "com.techsmith.snagit*"             # Snagit
    "com.techsmith.camtasia*"           # Camtasia
    "com.obsidianapp.screenrecorder"    # Screen Recorder
    "com.kap.Kap"                       # Kap
    "com.getkap.*"                      # Kap legacy
    "com.linebreak.CloudApp"            # CloudApp
    "com.droplr.droplr-mac"             # Droplr

    # ============================================================================
    # Media & Entertainment
    # ============================================================================
    "com.spotify.client"       # Spotify
    "com.apple.Music"          # Apple Music
    "com.apple.podcasts"       # Apple Podcasts
    "com.apple.BKAgentService" # Apple Books (Agent)
    "com.apple.iBooksX"        # Apple Books
    "com.apple.iBooks"         # Apple Books (Legacy)
    "com.apple.FinalCutPro"    # Final Cut Pro
    "com.apple.Motion"         # Motion
    "com.apple.Compressor"     # Compressor
    "com.blackmagic-design.*"  # DaVinci Resolve
    "com.colliderli.iina"      # IINA
    "org.videolan.vlc"         # VLC
    "io.mpv"                   # MPV
    "com.noodlesoft.Hazel"     # Hazel (automation)
    "tv.plex.player.desktop"   # Plex
    "com.netease.163music"     # NetEase Music

    # ============================================================================
    # License Management & App Stores
    # ============================================================================
    "com.paddle.Paddle*"          # Paddle (license management)
    "com.setapp.DesktopClient"    # Setapp
    "com.devmate.*"               # DevMate (license framework)
    "org.sparkle-project.Sparkle" # Sparkle (update framework)
)

# Legacy function - preserved for backward compatibility
# Use should_protect_from_uninstall() or should_protect_data() instead
readonly PRESERVED_BUNDLE_PATTERNS=("${SYSTEM_CRITICAL_BUNDLES[@]}" "${DATA_PROTECTED_BUNDLES[@]}")

# Check whether a bundle ID matches a pattern (supports globs)
bundle_matches_pattern() {
    local bundle_id="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    # Use bash [[  ]] for glob pattern matching (works with variables in bash 3.2+)
    # shellcheck disable=SC2053  # allow glob pattern matching
    if [[ "$bundle_id" == $pattern ]]; then
        return 0
    fi
    return 1
}

# Check if app is a system component that should never be uninstalled
should_protect_from_uninstall() {
    local bundle_id="$1"
    for pattern in "${SYSTEM_CRITICAL_BUNDLES[@]}"; do
        if bundle_matches_pattern "$bundle_id" "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check if app data should be protected during cleanup (but app can be uninstalled)
should_protect_data() {
    local bundle_id="$1"
    # Protect both system critical and data protected bundles during cleanup
    for pattern in "${SYSTEM_CRITICAL_BUNDLES[@]}" "${DATA_PROTECTED_BUNDLES[@]}"; do
        if bundle_matches_pattern "$bundle_id" "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check if a specific path should be protected from deletion
# Centralized logic to protect system settings, control center, and critical apps
#
# Args: $1 - path to check
# Returns: 0 if protected, 1 if safe to delete
should_protect_path() {
    local path="$1"
    [[ -z "$path" ]] && return 1

    local path_lower
    path_lower=$(echo "$path" | tr '[:upper:]' '[:lower:]')

    # 1. Check for explicit critical system keywords in path (case-insensitive)
    # Protect System Settings, Preferences, Control Center, and related XPC services
    # Also protect "Settings" (used in macOS Sequoia) and savedState files
    if [[ "$path_lower" =~ systemsettings || "$path_lower" =~ systempreferences || "$path_lower" =~ controlcenter ]]; then
        return 0
    fi

    # Additional check for com.apple.Settings (macOS Sequoia System Settings)
    if [[ "$path_lower" =~ com\.apple\.settings ]]; then
        return 0
    fi

    # 2. Protect system-critical cache directories that cause UI corruption
    # These caches are essential for modern macOS (Sonoma/Sequoia) system UI rendering
    case "$path" in
        # System Settings and Control Center caches (CRITICAL - prevents blank panel bug)
        *com.apple.systempreferences.cache* | *com.apple.Settings.cache* | *com.apple.controlcenter.cache*)
            return 0
            ;;
        # Finder and Dock (system essential)
        *com.apple.finder.cache* | *com.apple.dock.cache*)
            return 0
            ;;
        # System XPC services and sandboxed containers
        */Library/Containers/com.apple.Settings* | */Library/Containers/com.apple.SystemSettings* | */Library/Containers/com.apple.controlcenter*)
            return 0
            ;;
        */Library/Group\ Containers/com.apple.systempreferences* | */Library/Group\ Containers/com.apple.Settings*)
            return 0
            ;;
    esac

    # 3. Extract bundle ID from app container/group container paths
    # Matches: .../Library/Containers/bundle.id/...
    # Matches: .../Library/Group Containers/group.id/...
    if [[ "$path" =~ /Library/Containers/([^/]+) ]] || [[ "$path" =~ /Library/Group\ Containers/([^/]+) ]]; then
        local bundle_id="${BASH_REMATCH[1]}"
        if should_protect_data "$bundle_id"; then
            return 0
        fi
    fi

    # 4. Check for specific hardcoded critical patterns
    case "$path" in
        *com.apple.Settings* | *com.apple.SystemSettings* | *com.apple.controlcenter* | *com.apple.finder*)
            return 0
            ;;
    esac

    # 5. Check the full path against protected patterns (Broad Glob Match)
    # This catches things like /Users/tw93/Library/Caches/Claude when pattern is *Claude*
    for pattern in "${SYSTEM_CRITICAL_BUNDLES[@]}" "${DATA_PROTECTED_BUNDLES[@]}"; do
        if bundle_matches_pattern "$path" "$pattern"; then
            return 0
        fi
    done

    # 6. Check if the filename itself matches any protected patterns
    local filename
    filename=$(basename "$path")
    if should_protect_data "$filename"; then
        return 0
    fi

    return 1
}

# Find and list app-related files (consolidated from duplicates)
find_app_files() {
    local bundle_id="$1"
    local app_name="$2"
    local -a files_to_clean=()

    # ============================================================================
    # User-level files (no sudo required)
    # ============================================================================

    # Application Support
    [[ -d ~/Library/Application\ Support/"$app_name" ]] && files_to_clean+=("$HOME/Library/Application Support/$app_name")
    [[ -d ~/Library/Application\ Support/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Application Support/$bundle_id")

    # Sanitized App Name (remove spaces) - e.g. "Visual Studio Code" -> "VisualStudioCode"
    if [[ ${#app_name} -gt 3 && "$app_name" =~ [[:space:]] ]]; then
        local nospace_name="${app_name// /}"
        [[ -d ~/Library/Application\ Support/"$nospace_name" ]] && files_to_clean+=("$HOME/Library/Application Support/$nospace_name")
        [[ -d ~/Library/Caches/"$nospace_name" ]] && files_to_clean+=("$HOME/Library/Caches/$nospace_name")
        [[ -d ~/Library/Logs/"$nospace_name" ]] && files_to_clean+=("$HOME/Library/Logs/$nospace_name")

        local underscore_name="${app_name// /_}"
        [[ -d ~/Library/Application\ Support/"$underscore_name" ]] && files_to_clean+=("$HOME/Library/Application Support/$underscore_name")
    fi

    # Caches
    [[ -d ~/Library/Caches/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Caches/$bundle_id")
    [[ -d ~/Library/Caches/"$app_name" ]] && files_to_clean+=("$HOME/Library/Caches/$app_name")

    # Preferences
    [[ -f ~/Library/Preferences/"$bundle_id".plist ]] && files_to_clean+=("$HOME/Library/Preferences/$bundle_id.plist")
    [[ -d ~/Library/Preferences/ByHost ]] && while IFS= read -r -d '' pref; do
        files_to_clean+=("$pref")
    done < <(find ~/Library/Preferences/ByHost \( -name "$bundle_id*.plist" \) -print0 2> /dev/null)

    # Logs
    [[ -d ~/Library/Logs/"$app_name" ]] && files_to_clean+=("$HOME/Library/Logs/$app_name")
    [[ -d ~/Library/Logs/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Logs/$bundle_id")
    # CrashReporter
    [[ -d ~/Library/Application\ Support/CrashReporter/"$app_name" ]] && files_to_clean+=("$HOME/Library/Application Support/CrashReporter/$app_name")

    # Saved Application State
    [[ -d ~/Library/Saved\ Application\ State/"$bundle_id".savedState ]] && files_to_clean+=("$HOME/Library/Saved Application State/$bundle_id.savedState")

    # Containers (sandboxed apps)
    [[ -d ~/Library/Containers/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Containers/$bundle_id")

    # Group Containers
    [[ -d ~/Library/Group\ Containers ]] && while IFS= read -r -d '' container; do
        files_to_clean+=("$container")
    done < <(find ~/Library/Group\ Containers -type d \( -name "*$bundle_id*" \) -print0 2> /dev/null)

    # WebKit data
    [[ -d ~/Library/WebKit/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/WebKit/$bundle_id")
    [[ -d ~/Library/WebKit/com.apple.WebKit.WebContent/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/WebKit/com.apple.WebKit.WebContent/$bundle_id")

    # HTTP Storage
    [[ -d ~/Library/HTTPStorages/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/HTTPStorages/$bundle_id")

    # Cookies
    [[ -f ~/Library/Cookies/"$bundle_id".binarycookies ]] && files_to_clean+=("$HOME/Library/Cookies/$bundle_id.binarycookies")

    # Launch Agents (user-level)
    [[ -f ~/Library/LaunchAgents/"$bundle_id".plist ]] && files_to_clean+=("$HOME/Library/LaunchAgents/$bundle_id.plist")
    # Search for LaunchAgents by app name if unique enough
    if [[ ${#app_name} -gt 3 ]]; then
        while IFS= read -r -d '' plist; do
            files_to_clean+=("$plist")
        done < <(find ~/Library/LaunchAgents -name "*$app_name*.plist" -print0 2> /dev/null)
    fi

    # Application Scripts
    [[ -d ~/Library/Application\ Scripts/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Application Scripts/$bundle_id")

    # Services
    [[ -d ~/Library/Services/"$app_name".workflow ]] && files_to_clean+=("$HOME/Library/Services/$app_name.workflow")

    # QuickLook Plugins
    [[ -d ~/Library/QuickLook/"$app_name".qlgenerator ]] && files_to_clean+=("$HOME/Library/QuickLook/$app_name.qlgenerator")

    # Internet Plug-Ins
    [[ -d ~/Library/Internet\ Plug-Ins/"$app_name".plugin ]] && files_to_clean+=("$HOME/Library/Internet Plug-Ins/$app_name.plugin")

    # Audio Plug-Ins (Components, VST, VST3)
    [[ -d ~/Library/Audio/Plug-Ins/Components/"$app_name".component ]] && files_to_clean+=("$HOME/Library/Audio/Plug-Ins/Components/$app_name.component")
    [[ -d ~/Library/Audio/Plug-Ins/VST/"$app_name".vst ]] && files_to_clean+=("$HOME/Library/Audio/Plug-Ins/VST/$app_name.vst")
    [[ -d ~/Library/Audio/Plug-Ins/VST3/"$app_name".vst3 ]] && files_to_clean+=("$HOME/Library/Audio/Plug-Ins/VST3/$app_name.vst3")
    [[ -d ~/Library/Audio/Plug-Ins/Digidesign/"$app_name".dpm ]] && files_to_clean+=("$HOME/Library/Audio/Plug-Ins/Digidesign/$app_name.dpm")

    # Preference Panes
    [[ -d ~/Library/PreferencePanes/"$app_name".prefPane ]] && files_to_clean+=("$HOME/Library/PreferencePanes/$app_name.prefPane")

    # Screen Savers
    [[ -d ~/Library/Screen\ Savers/"$app_name".saver ]] && files_to_clean+=("$HOME/Library/Screen Savers/$app_name.saver")

    # Frameworks
    [[ -d ~/Library/Frameworks/"$app_name".framework ]] && files_to_clean+=("$HOME/Library/Frameworks/$app_name.framework")

    # Autosave Information
    [[ -d ~/Library/Autosave\ Information/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Autosave Information/$bundle_id")

    # Contextual Menu Items
    [[ -d ~/Library/Contextual\ Menu\ Items/"$app_name".plugin ]] && files_to_clean+=("$HOME/Library/Contextual Menu Items/$app_name.plugin")

    # Spotlight Plugins
    [[ -d ~/Library/Spotlight/"$app_name".mdimporter ]] && files_to_clean+=("$HOME/Library/Spotlight/$app_name.mdimporter")

    # Color Pickers
    [[ -d ~/Library/ColorPickers/"$app_name".colorPicker ]] && files_to_clean+=("$HOME/Library/ColorPickers/$app_name.colorPicker")

    # Workflows
    [[ -d ~/Library/Workflows/"$app_name".workflow ]] && files_to_clean+=("$HOME/Library/Workflows/$app_name.workflow")

    # Unix-style configuration directories and files (cross-platform apps)
    [[ -d ~/.config/"$app_name" ]] && files_to_clean+=("$HOME/.config/$app_name")
    [[ -d ~/.local/share/"$app_name" ]] && files_to_clean+=("$HOME/.local/share/$app_name")
    [[ -d ~/."$app_name" ]] && files_to_clean+=("$HOME/.$app_name")
    [[ -f ~/."${app_name}rc" ]] && files_to_clean+=("$HOME/.${app_name}rc")

    # ============================================================================
    # IDE-specific SDK and Toolchain directories
    # ============================================================================

    # DevEco-Studio (HarmonyOS/OpenHarmony IDE by Huawei)
    if [[ "$app_name" =~ DevEco|deveco ]] || [[ "$bundle_id" =~ huawei.*deveco ]]; then
        [[ -d ~/DevEcoStudioProjects ]] && files_to_clean+=("$HOME/DevEcoStudioProjects")
        [[ -d ~/DevEco-Studio ]] && files_to_clean+=("$HOME/DevEco-Studio")
        [[ -d ~/Library/Application\ Support/Huawei ]] && files_to_clean+=("$HOME/Library/Application Support/Huawei")
        [[ -d ~/Library/Caches/Huawei ]] && files_to_clean+=("$HOME/Library/Caches/Huawei")
        [[ -d ~/Library/Logs/Huawei ]] && files_to_clean+=("$HOME/Library/Logs/Huawei")
        [[ -d ~/Library/Huawei ]] && files_to_clean+=("$HOME/Library/Huawei")
        [[ -d ~/Huawei ]] && files_to_clean+=("$HOME/Huawei")
        [[ -d ~/HarmonyOS ]] && files_to_clean+=("$HOME/HarmonyOS")
        [[ -d ~/.huawei ]] && files_to_clean+=("$HOME/.huawei")
        [[ -d ~/.ohos ]] && files_to_clean+=("$HOME/.ohos")
    fi

    # Android Studio
    if [[ "$app_name" =~ Android.*Studio|android.*studio ]] || [[ "$bundle_id" =~ google.*android.*studio|jetbrains.*android ]]; then
        [[ -d ~/AndroidStudioProjects ]] && files_to_clean+=("$HOME/AndroidStudioProjects")
        [[ -d ~/Library/Android ]] && files_to_clean+=("$HOME/Library/Android")
        [[ -d ~/.android ]] && files_to_clean+=("$HOME/.android")
        [[ -d ~/.gradle ]] && files_to_clean+=("$HOME/.gradle")
        [[ -d ~/Library/Application\ Support/Google ]] &&
            while IFS= read -r -d '' dir; do files_to_clean+=("$dir"); done < <(find ~/Library/Application\ Support/Google -maxdepth 1 -name "AndroidStudio*" -print0 2> /dev/null)
    fi

    # Xcode
    if [[ "$app_name" =~ Xcode|xcode ]] || [[ "$bundle_id" =~ apple.*xcode ]]; then
        [[ -d ~/Library/Developer ]] && files_to_clean+=("$HOME/Library/Developer")
        [[ -d ~/.Xcode ]] && files_to_clean+=("$HOME/.Xcode")
    fi

    # IntelliJ IDEA, PyCharm, WebStorm, etc. (JetBrains IDEs)
    if [[ "$bundle_id" =~ jetbrains ]] || [[ "$app_name" =~ IntelliJ|PyCharm|WebStorm|GoLand|RubyMine|PhpStorm|CLion|DataGrip|Rider ]]; then
        local ide_name="$app_name"
        [[ -d ~/Library/Application\ Support/JetBrains ]] &&
            while IFS= read -r -d '' dir; do files_to_clean+=("$dir"); done < <(find ~/Library/Application\ Support/JetBrains -maxdepth 1 -name "${ide_name}*" -print0 2> /dev/null)
        [[ -d ~/Library/Caches/JetBrains ]] &&
            while IFS= read -r -d '' dir; do files_to_clean+=("$dir"); done < <(find ~/Library/Caches/JetBrains -maxdepth 1 -name "${ide_name}*" -print0 2> /dev/null)
        [[ -d ~/Library/Logs/JetBrains ]] &&
            while IFS= read -r -d '' dir; do files_to_clean+=("$dir"); done < <(find ~/Library/Logs/JetBrains -maxdepth 1 -name "${ide_name}*" -print0 2> /dev/null)
    fi

    # Unity
    if [[ "$app_name" =~ Unity|unity ]] || [[ "$bundle_id" =~ unity ]]; then
        [[ -d ~/.local/share/unity3d ]] && files_to_clean+=("$HOME/.local/share/unity3d")
        [[ -d ~/Library/Unity ]] && files_to_clean+=("$HOME/Library/Unity")
    fi

    # Unreal Engine
    if [[ "$app_name" =~ Unreal|unreal ]] || [[ "$bundle_id" =~ unrealengine|epicgames ]]; then
        [[ -d ~/Library/Application\ Support/Epic ]] && files_to_clean+=("$HOME/Library/Application Support/Epic")
        [[ -d ~/Documents/Unreal\ Projects ]] && files_to_clean+=("$HOME/Documents/Unreal Projects")
    fi

    # Visual Studio Code
    if [[ "$bundle_id" =~ microsoft.*vscode|visualstudio.*code ]]; then
        [[ -d ~/.vscode ]] && files_to_clean+=("$HOME/.vscode")
        [[ -d ~/.vscode-insiders ]] && files_to_clean+=("$HOME/.vscode-insiders")
    fi

    # Flutter
    if [[ "$app_name" =~ Flutter|flutter ]] || [[ "$bundle_id" =~ flutter ]]; then
        [[ -d ~/.pub-cache ]] && files_to_clean+=("$HOME/.pub-cache")
        [[ -d ~/flutter ]] && files_to_clean+=("$HOME/flutter")
    fi

    # Godot
    if [[ "$app_name" =~ Godot|godot ]] || [[ "$bundle_id" =~ godot ]]; then
        [[ -d ~/.local/share/godot ]] && files_to_clean+=("$HOME/.local/share/godot")
        [[ -d ~/Library/Application\ Support/Godot ]] && files_to_clean+=("$HOME/Library/Application Support/Godot")
    fi

    # Docker Desktop
    if [[ "$app_name" =~ Docker ]] || [[ "$bundle_id" =~ docker ]]; then
        [[ -d ~/.docker ]] && files_to_clean+=("$HOME/.docker")
    fi

    # Only print if array has elements to avoid unbound variable error
    if [[ ${#files_to_clean[@]} -gt 0 ]]; then
        printf '%s\n' "${files_to_clean[@]}"
    fi
}

# Find system-level app files (requires sudo)
find_app_system_files() {
    local bundle_id="$1"
    local app_name="$2"
    local -a system_files=()

    # System Application Support
    [[ -d /Library/Application\ Support/"$app_name" ]] && system_files+=("/Library/Application Support/$app_name")
    [[ -d /Library/Application\ Support/"$bundle_id" ]] && system_files+=("/Library/Application Support/$bundle_id")

    # Sanitized App Name (remove spaces)
    if [[ ${#app_name} -gt 3 && "$app_name" =~ [[:space:]] ]]; then
        local nospace_name="${app_name// /}"
        [[ -d /Library/Application\ Support/"$nospace_name" ]] && system_files+=("/Library/Application Support/$nospace_name")
        [[ -d /Library/Caches/"$nospace_name" ]] && system_files+=("/Library/Caches/$nospace_name")
        [[ -d /Library/Logs/"$nospace_name" ]] && system_files+=("/Library/Logs/$nospace_name")
    fi

    # System Launch Agents
    [[ -f /Library/LaunchAgents/"$bundle_id".plist ]] && system_files+=("/Library/LaunchAgents/$bundle_id.plist")
    # Search for LaunchAgents by app name if unique enough
    if [[ ${#app_name} -gt 3 ]]; then
        while IFS= read -r -d '' plist; do
            system_files+=("$plist")
        done < <(find /Library/LaunchAgents -name "*$app_name*.plist" -print0 2> /dev/null)
    fi

    # System Launch Daemons
    [[ -f /Library/LaunchDaemons/"$bundle_id".plist ]] && system_files+=("/Library/LaunchDaemons/$bundle_id.plist")
    # Search for LaunchDaemons by app name if unique enough
    if [[ ${#app_name} -gt 3 ]]; then
        while IFS= read -r -d '' plist; do
            system_files+=("$plist")
        done < <(find /Library/LaunchDaemons -name "*$app_name*.plist" -print0 2> /dev/null)
    fi

    # Privileged Helper Tools
    [[ -d /Library/PrivilegedHelperTools ]] && while IFS= read -r -d '' helper; do
        system_files+=("$helper")
    done < <(find /Library/PrivilegedHelperTools \( -name "$bundle_id*" \) -print0 2> /dev/null)

    # System Preferences
    [[ -f /Library/Preferences/"$bundle_id".plist ]] && system_files+=("/Library/Preferences/$bundle_id.plist")

    # Installation Receipts
    [[ -d /private/var/db/receipts ]] && while IFS= read -r -d '' receipt; do
        system_files+=("$receipt")
    done < <(find /private/var/db/receipts \( -name "*$bundle_id*" \) -print0 2> /dev/null)

    # System Logs
    [[ -d /Library/Logs/"$app_name" ]] && system_files+=("/Library/Logs/$app_name")
    [[ -d /Library/Logs/"$bundle_id" ]] && system_files+=("/Library/Logs/$bundle_id")

    # System Frameworks
    [[ -d /Library/Frameworks/"$app_name".framework ]] && system_files+=("/Library/Frameworks/$app_name.framework")

    # System Internet Plug-Ins
    [[ -d /Library/Internet\ Plug-Ins/"$app_name".plugin ]] && system_files+=("/Library/Internet Plug-Ins/$app_name.plugin")

    # System Audio Plug-Ins
    [[ -d /Library/Audio/Plug-Ins/Components/"$app_name".component ]] && system_files+=("/Library/Audio/Plug-Ins/Components/$app_name.component")
    [[ -d /Library/Audio/Plug-Ins/VST/"$app_name".vst ]] && system_files+=("/Library/Audio/Plug-Ins/VST/$app_name.vst")
    [[ -d /Library/Audio/Plug-Ins/VST3/"$app_name".vst3 ]] && system_files+=("/Library/Audio/Plug-Ins/VST3/$app_name.vst3")
    [[ -d /Library/Audio/Plug-Ins/Digidesign/"$app_name".dpm ]] && system_files+=("/Library/Audio/Plug-Ins/Digidesign/$app_name.dpm")

    # System QuickLook Plugins
    [[ -d /Library/QuickLook/"$app_name".qlgenerator ]] && system_files+=("/Library/QuickLook/$app_name.qlgenerator")

    # System Preference Panes
    [[ -d /Library/PreferencePanes/"$app_name".prefPane ]] && system_files+=("/Library/PreferencePanes/$app_name.prefPane")

    # System Screen Savers
    [[ -d /Library/Screen\ Savers/"$app_name".saver ]] && system_files+=("/Library/Screen Savers/$app_name.saver")

    # System Caches
    [[ -d /Library/Caches/"$bundle_id" ]] && system_files+=("/Library/Caches/$bundle_id")
    [[ -d /Library/Caches/"$app_name" ]] && system_files+=("/Library/Caches/$app_name")

    # Only print if array has elements
    if [[ ${#system_files[@]} -gt 0 ]]; then
        printf '%s\n' "${system_files[@]}"
    fi

    # Find files from receipts (Deep Scan)
    find_app_receipt_files "$bundle_id"
}

# Find files from installation receipts (Bom files)
find_app_receipt_files() {
    local bundle_id="$1"

    # Skip if no bundle ID
    [[ -z "$bundle_id" || "$bundle_id" == "unknown" ]] && return 0

    local -a receipt_files=()
    local -a bom_files=()

    # Find receipts matching the bundle ID
    # Usually in /var/db/receipts/
    if [[ -d /private/var/db/receipts ]]; then
        while IFS= read -r -d '' bom; do
            bom_files+=("$bom")
        done < <(find /private/var/db/receipts -name "${bundle_id}*.bom" -print0 2> /dev/null)
    fi

    # Process bom files if any found
    if [[ ${#bom_files[@]} -gt 0 ]]; then
        for bom_file in "${bom_files[@]}"; do
            [[ ! -f "$bom_file" ]] && continue

            # Parse bom file
            # lsbom -f: file paths only
            # -s: suppress output (convert to text)
            local bom_content
            bom_content=$(lsbom -f -s "$bom_file" 2> /dev/null)

            while IFS= read -r file_path; do
                # Standardize path (remove leading dot)
                local clean_path="${file_path#.}"

                # Ensure it starts with /
                if [[ "$clean_path" != /* ]]; then
                    clean_path="/$clean_path"
                fi

                # ------------------------------------------------------------------------
                # SAFETY FILTER: Only allow specific removal paths
                # ------------------------------------------------------------------------
                local is_safe=false

                # Whitelisted prefixes
                case "$clean_path" in
                    /Applications/*) is_safe=true ;;
                    /Users/*) is_safe=true ;;
                    /usr/local/*) is_safe=true ;;
                    /opt/*) is_safe=true ;;
                    /Library/*)
                        # Filter sub-paths in /Library to avoid system damage
                        # Allow safely: Application Support, Caches, Logs, Preferences
                        case "$clean_path" in
                            /Library/Application\ Support/*) is_safe=true ;;
                            /Library/Caches/*) is_safe=true ;;
                            /Library/Logs/*) is_safe=true ;;
                            /Library/Preferences/*) is_safe=true ;;
                            /Library/PrivilegedHelperTools/*) is_safe=true ;;
                            /Library/LaunchAgents/*) is_safe=true ;;
                            /Library/LaunchDaemons/*) is_safe=true ;;
                            /Library/Internet\ Plug-Ins/*) is_safe=true ;;
                            /Library/Audio/Plug-Ins/*) is_safe=true ;;
                            /Library/Extensions/*) is_safe=false ;; # Default unsafe
                            *) is_safe=false ;;
                        esac
                        ;;
                esac

                # Hard blocks
                case "$clean_path" in
                    /System/* | /usr/bin/* | /usr/lib/* | /bin/* | /sbin/*) is_safe=false ;;
                esac

                if [[ "$is_safe" == "true" && -e "$clean_path" ]]; then
                    # Only valid files
                    # Don't delete directories if they are non-empty parents?
                    # lsbom lists directories too.
                    # If we return a directory, `safe_remove` logic handles it.
                    # `uninstall.sh` uses `remove_file_list`.
                    # If `lsbom` lists `/Applications` (it shouldn't, only contents), we must be careful.
                    # `lsbom` usually lists `./Applications/MyApp.app`.
                    # If it lists `./Applications`, we must skip it.

                    # Extra check: path must be deep enough?
                    # If path is just "/Applications", skip.
                    if [[ "$clean_path" == "/Applications" || "$clean_path" == "/Library" || "$clean_path" == "/usr/local" ]]; then
                        continue
                    fi

                    receipt_files+=("$clean_path")
                fi

            done <<< "$bom_content"
        done
    fi
    if [[ ${#receipt_files[@]} -gt 0 ]]; then
        printf '%s\n' "${receipt_files[@]}"
    fi
}

# Force quit an application
force_kill_app() {
    # Args: app_name [app_path]; tries graceful then force kill; returns 0 if stopped, 1 otherwise
    local app_name="$1"
    local app_path="${2:-""}"

    # Get the executable name from bundle if app_path is provided
    local exec_name=""
    if [[ -n "$app_path" && -e "$app_path/Contents/Info.plist" ]]; then
        exec_name=$(defaults read "$app_path/Contents/Info.plist" CFBundleExecutable 2> /dev/null || echo "")
    fi

    # Use executable name for precise matching, fallback to app name
    local match_pattern="${exec_name:-$app_name}"

    # Check if process is running using exact match only
    if ! pgrep -x "$match_pattern" > /dev/null 2>&1; then
        return 0
    fi

    # Try graceful termination first
    pkill -x "$match_pattern" 2> /dev/null || true
    sleep 2

    # Check again after graceful kill
    if ! pgrep -x "$match_pattern" > /dev/null 2>&1; then
        return 0
    fi

    # Force kill if still running
    pkill -9 -x "$match_pattern" 2> /dev/null || true
    sleep 2

    # If still running and sudo is available, try with sudo
    if pgrep -x "$match_pattern" > /dev/null 2>&1; then
        if sudo -n true 2> /dev/null; then
            sudo pkill -9 -x "$match_pattern" 2> /dev/null || true
            sleep 2
        fi
    fi

    # Final check with longer timeout for stubborn processes
    local retries=3
    while [[ $retries -gt 0 ]]; do
        if ! pgrep -x "$match_pattern" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((retries--))
    done

    # Still running after all attempts
    pgrep -x "$match_pattern" > /dev/null 2>&1 && return 1 || return 0
}

# Calculate total size of files (consolidated from duplicates)
calculate_total_size() {
    local files="$1"
    local total_kb=0

    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local size_kb
            size_kb=$(get_path_size_kb "$file")
            ((total_kb += size_kb))
        fi
    done <<< "$files"

    echo "$total_kb"
}
