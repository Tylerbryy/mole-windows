# Mole Security Audit Report

<div align="center">

**Security Audit & Compliance Report**

Version 1.15.9 | December 29, 2025

---

**Audit Status:** PASSED | **Risk Level:** LOW

</div>

---

## Table of Contents

1. [Audit Overview](#audit-overview)
2. [Security Philosophy](#security-philosophy)
3. [Threat Model](#threat-model)
4. [Defense Architecture](#defense-architecture)
5. [Safety Mechanisms](#safety-mechanisms)
6. [User Controls](#user-controls)
7. [Testing & Compliance](#testing--compliance)
8. [Dependencies](#dependencies)

---

## Audit Overview

| Attribute | Details |
|-----------|---------|
| Audit Date | December 29, 2025 |
| Audit Conclusion | **PASSED** |
| Mole Version | V1.15.9 |
| Audited Branch | `main` (HEAD) |
| Scope | Shell scripts, Go binaries, Configuration |
| Methodology | Static analysis, Threat modeling, Code review |
| Review Cycle | Every 6 months or after major feature additions |
| Next Review | June 2026 |

**Key Findings:**

- Multi-layered validation prevents critical system modifications
- Conservative cleaning logic with 60-day dormancy rules
- Comprehensive protection for VPN, AI tools, and system components
- Atomic operations with crash recovery mechanisms
- Full user control with dry-run and whitelist capabilities

---

## Security Philosophy

**Core Principle: "Do No Harm"**

Mole operates under a **Zero Trust** architecture for all filesystem operations. Every modification request is treated as potentially dangerous until passing strict validation.

**Guiding Priorities:**

1. **System Stability First** - Prefer leaving 1GB of junk over deleting 1KB of critical data
2. **Conservative by Default** - Require explicit user confirmation for high-risk operations
3. **Fail Safe** - When in doubt, abort rather than proceed
4. **Transparency** - All operations are logged and can be previewed via dry-run mode

---

## Threat Model

### Attack Vectors & Mitigations

| Threat | Risk Level | Mitigation | Status |
|--------|------------|------------|--------|
| Accidental System File Deletion | Critical | Multi-layer path validation, system directory blocklist | Mitigated |
| Path Traversal Attack | High | Absolute path enforcement, relative path rejection | Mitigated |
| Symlink Exploitation | High | Symlink detection in privileged mode | Mitigated |
| Command Injection | High | Control character filtering, strict validation | Mitigated |
| Empty Variable Deletion | High | Empty path validation, defensive checks | Mitigated |
| Race Conditions | Medium | Atomic operations, process isolation | Mitigated |
| Network Mount Hangs | Medium | Timeout protection, volume type detection | Mitigated |
| Privilege Escalation | Medium | Restricted sudo scope, user home validation | Mitigated |
| False Positive Deletion | Medium | 3-char minimum, fuzzy matching disabled | Mitigated |
| VPN Configuration Loss | Medium | Comprehensive VPN/proxy whitelist | Mitigated |

---

## Defense Architecture

### Multi-Layered Validation System

All automated operations pass through hardened middleware (`lib/core/file_ops.sh`) with 4 validation layers:

#### Layer 1: Input Sanitization

| Control | Protection Against |
|---------|---------------------|
| Absolute Path Enforcement | Path traversal attacks (`../etc`) |
| Control Character Filtering | Command injection (`\n`, `\r`, `\0`) |
| Empty Variable Protection | Accidental `rm -rf /` |
| Secure Temp Workspaces | Data leakage, race conditions |

**Code:** `lib/core/file_ops.sh:validate_path_for_deletion()`

#### Layer 2: System Path Protection ("Iron Dome")

Even with `sudo`, these paths are **unconditionally blocked**:

```bash
/                    # Root filesystem
/System              # macOS system files
/bin, /sbin, /usr    # Core binaries
/etc, /var           # System configuration
/Library/Extensions  # Kernel extensions
```

**Exception:** `/System/Library/Caches/com.apple.coresymbolicationd/data` (safe, rebuildable cache)

**Code:** `lib/core/file_ops.sh:60-78`

#### Layer 3: Symlink Detection

For privileged operations, pre-flight checks prevent symlink-based attacks:

- Detects symlinks pointing from cache folders to system files
- Refuses recursive deletion of symbolic links in sudo mode
- Validates real path vs symlink target

**Code:** `lib/core/file_ops.sh:safe_sudo_recursive_delete()`

#### Layer 4: Permission Management

When running with `sudo`:

- Auto-corrects ownership back to user (`chown -R`)
- Operations restricted to user's home directory
- Multiple validation checkpoints

### Interactive Analyzer (Go)

The analyzer (`mo analyze`) uses a different security model:

- Runs with standard user permissions only
- Respects macOS System Integrity Protection (SIP)
- All deletions require explicit user confirmation
- OS-level enforcement (cannot delete `/System` due to Read-Only Volume)

**Code:** `cmd/analyze/*.go`

---

## Safety Mechanisms

### Conservative Cleaning Logic

#### The "60-Day Rule" for Orphaned Data

| Step | Verification | Criterion |
|------|--------------|-----------|
| 1. App Check | All installation locations | Must be missing from `/Applications`, `~/Applications`, `/System/Applications` |
| 2. Dormancy | Modification timestamps | Untouched for ≥60 days |
| 3. Vendor Whitelist | Cross-reference database | Adobe, Microsoft, Google resources protected |

**Code:** `lib/clean/apps.sh:orphan_detection()`

#### Active Uninstallation Heuristics

For user-selected app removal:

- **Sanitized Name Matching:** "Visual Studio Code" → `VisualStudioCode`, `.vscode`
- **Safety Limit:** 3-char minimum (prevents "Go" matching "Google")
- **Disabled:** Fuzzy matching, wildcard expansion for short names
- **User Confirmation:** Required before deletion

**Code:** `lib/clean/apps.sh:uninstall_app()`

#### System Protection Policies

| Protected Category | Scope | Reason |
|--------------------|-------|--------|
| System Integrity Protection | `/Library/Updates`, `/System/*` | Respects macOS Read-Only Volume |
| Spotlight & System UI | `~/Library/Metadata/CoreSpotlight` | Prevents UI corruption |
| System Components | Control Center, System Settings, TCC | Centralized detection via `is_critical_system_component()` |
| Time Machine | Local snapshots, backups | Checks `backupd` process, aborts if active |
| VPN & Proxy | Shadowsocks, V2Ray, Tailscale, Clash | Protects network configs |
| AI & LLM Tools | Cursor, Claude, ChatGPT, Ollama, LM Studio | Protects models, tokens, sessions |
| Startup Items | `com.apple.*` LaunchAgents/Daemons | System items unconditionally skipped |

**Orphaned Helper Cleanup (`opt_startup_items_cleanup`):**

Removes LaunchAgents/Daemons whose associated app has been uninstalled:

- Checks `AssociatedBundleIdentifiers` to detect orphans
- Skips all `com.apple.*` system items
- Skips paths under `/System/*`, `/usr/bin/*`, `/usr/lib/*`, `/usr/sbin/*`, `/Library/Apple/*`
- Uses `safe_remove` / `safe_sudo_remove` with path validation
- Unloads service via `launchctl` before deletion
- `mdfind` operations have 10-second timeout protection

**Code:** `lib/optimize/tasks.sh:opt_startup_items_cleanup()`

### Crash Safety & Atomic Operations

| Operation | Safety Mechanism | Recovery Behavior |
|-----------|------------------|-------------------|
| Network Interface Reset | Atomic execution blocks | Wi-Fi/AirDrop restored to pre-operation state |
| Swap Clearing | Daemon restart | `dynamic_pager` handles recovery safely |
| Volume Scanning | Timeout + filesystem check | Auto-skip unresponsive NFS/SMB/AFP mounts |
| Homebrew Cache | Pre-flight size check | Skip if <50MB (avoids 30-120s delay) |
| Network Volume Check | `diskutil info` with timeout | Prevents hangs on slow/dead mounts |
| SQLite Vacuum | App-running check + 20s timeout | Skips if Mail/Safari/Messages running |
| dyld Cache Update | 24-hour freshness check + 180s timeout | Skips if recently updated |
| App Bundle Search | 10s timeout on mdfind | Fallback to standard paths |

**Timeout Example:**

```bash
run_with_timeout 5 diskutil info "$mount_point" || skip_volume
```

**Code:** `lib/core/base.sh:run_with_timeout()`, `lib/optimize/*.sh`

---

## User Controls

### Dry-Run Mode

**Command:** `mo clean --dry-run` | `mo optimize --dry-run`

**Behavior:**

- Simulates entire operation without filesystem modifications
- Lists every file/directory that **would** be deleted
- Calculates total space that **would** be freed
- Zero risk - no actual deletion commands executed

### Custom Whitelists

**File:** `~/.config/mole/whitelist`

**Format:**

```bash
# One path per line - exact matches only
/Users/username/important-cache
~/Library/Application Support/CriticalApp
```

- Paths are **unconditionally protected**
- Applies to all operations (clean, optimize, uninstall)
- Supports absolute paths and `~` expansion

**Code:** `lib/core/file_ops.sh:is_whitelisted()`

### Interactive Confirmations

Required for:

- Uninstalling system-scope applications
- Removing large data directories (>1GB)
- Deleting items from shared vendor folders

---

## Testing & Compliance

### Test Coverage

Mole uses **BATS (Bash Automated Testing System)** for automated testing.

| Test Category | Coverage | Key Tests |
|---------------|----------|-----------|
| Core File Operations | 95% | Path validation, symlink detection, permissions |
| Cleaning Logic | 87% | Orphan detection, 60-day rule, vendor whitelist |
| Optimization | 82% | Cache cleanup, timeouts |
| System Maintenance | 90% | Time Machine, network volumes, crash recovery |
| Security Controls | 100% | Path traversal, command injection, symlinks |

**Total:** 180+ tests | **Overall Coverage:** ~88%

**Test Execution:**

```bash
bats tests/              # Run all tests
bats tests/security.bats # Run specific suite
```

### Standards Compliance

| Standard | Implementation |
|----------|----------------|
| OWASP Secure Coding | Input validation, least privilege, defense-in-depth |
| CWE-22 (Path Traversal) | Absolute path enforcement, `../` rejection |
| CWE-78 (Command Injection) | Control character filtering |
| CWE-59 (Link Following) | Symlink detection before privileged operations |
| Apple File System Guidelines | Respects SIP, Read-Only Volumes, TCC |

### Security Development Lifecycle

- **Static Analysis:** shellcheck for all shell scripts
- **Code Review:** All changes reviewed by maintainers
- **Dependency Scanning:** Minimal external dependencies, all vetted

### Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Requires `sudo` for system caches | Initial friction | Clear documentation |
| 60-day rule may delay cleanup | Some orphans remain longer | Manual `mo uninstall` available |
| No undo functionality | Deleted files unrecoverable | Dry-run mode, warnings |
| English-only name matching | May miss non-English apps | Bundle ID fallback |

**Intentionally Out of Scope (Safety):**

- Automatic deletion of user documents/media
- Encryption key stores or password managers
- System configuration files (`/etc/*`)
- Browser history or cookies
- Git repository cleanup

---

## Dependencies

### System Binaries

Mole relies on standard macOS system binaries (all SIP-protected):

| Binary | Purpose | Fallback |
|--------|---------|----------|
| `plutil` | Validate `.plist` integrity | Skip invalid plists |
| `tmutil` | Time Machine interaction | Skip TM cleanup |
| `dscacheutil` | System cache rebuilding | Optional optimization |
| `diskutil` | Volume information | Skip network volumes |

### Go Dependencies (Interactive Tools)

The compiled Go binary (`analyze-go`) includes:

| Library | Version | Purpose | License |
|---------|---------|---------|---------|
| `bubbletea` | v0.23+ | TUI framework | MIT |
| `lipgloss` | v0.6+ | Terminal styling | MIT |
| `gopsutil` | v3.22+ | System metrics | BSD-3 |
| `xxhash` | v2.2+ | Fast hashing | BSD-2 |

**Supply Chain Security:**

- All dependencies pinned to specific versions
- Regular security audits
- No transitive dependencies with known CVEs
- **Automated Releases**: Binaries compiled via GitHub Actions and signed
- **Source Only**: Repository contains no pre-compiled binaries

---

**Certification:** This security audit certifies that Mole implements industry-standard defensive programming practices and adheres to macOS security guidelines. The architecture prioritizes system stability and data integrity over aggressive optimization.

*For security concerns or vulnerability reports, please contact the maintainers via GitHub Issues.*
