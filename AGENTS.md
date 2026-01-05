# AGENTS.md - Development Guide for Mole

This guide provides AI coding assistants with essential commands, patterns, and conventions for working in the Mole codebase.

**Quick reference**: Build/test commands • Safety rules • Architecture map • Code style

---

## Safety Checklist

Before any operation:

- Use `safe_*` helpers (never raw `rm -rf` or `find -delete`)
- Check protection: `is_protected()`, `is_whitelisted()`
- Test first: `MO_DRY_RUN=1 ./mole clean`
- Validate syntax: `bash -n <file>`
- Run tests: `./scripts/test.sh`

## NEVER Do These

- Run `rm -rf` or any raw deletion commands
- Delete files without checking protection lists
- Modify system-critical paths (e.g., `/System`, `/Library/Apple`)
- Remove installer flags `--prefix`/`--config` from `install.sh`
- Commit code changes unless explicitly requested
- Run destructive operations without dry-run validation
- Use raw `git` commands when `gh` CLI is available

## ALWAYS Do These

- Use `safe_*` helper functions for deletions (`safe_rm`, `safe_find_delete`)
- Respect whitelist files (e.g., `~/.config/mole/whitelist`)
- Check protection logic before cleanup operations
- Test with dry-run modes first
- Validate syntax before suggesting changes: `bash -n <file>`
- Use `gh` CLI for all GitHub operations (issues, PRs, releases, etc.)
- Never commit code unless explicitly requested by user

---

## Quick Reference

### Build Commands
```bash
# Build Go binaries for current platform
make build

# Build release binaries (cross-platform)
make release-amd64  # macOS Intel
make release-arm64   # macOS Apple Silicon

# Clean build artifacts
make clean
```

### Test Commands
```bash
# Run full test suite (recommended before commits)
./scripts/test.sh

# Run specific BATS test file
bats tests/clean.bats

# Run specific test case by name
bats tests/clean.bats -f "should respect whitelist"

# Run Go tests only
go test -v ./cmd/...

# Run Go tests for specific package
go test -v ./cmd/analyze

# Shell syntax check
bash -n lib/clean/user.sh
bash -n mole

# Lint shell scripts
shellcheck --rcfile .shellcheckrc lib/**/*.sh bin/**/*.sh
```

### Development Commands
```bash
# Test cleanup in dry-run mode
MO_DRY_RUN=1 ./mole clean

# Enable debug logging
MO_DEBUG=1 ./mole clean

# Test Go tool directly
go run ./cmd/analyze

# Test installation locally
./install.sh --prefix /usr/local/bin --config ~/.config/mole
```

---

## Architecture Quick Map

```
mole/                      # Main CLI entrypoint (menu + routing)
├── mo                     # CLI alias wrapper
├── install.sh             # Manual installer/updater (preserves --prefix/--config)
├── bin/                   # Command entry points (thin wrappers)
│   ├── clean.sh           # Deep cleanup orchestrator
│   ├── uninstall.sh       # App removal with leftover detection
│   ├── optimize.sh        # Cache rebuild + service refresh
│   ├── purge.sh           # Aggressive cleanup mode
│   ├── touchid.sh         # Touch ID sudo enabler
│   ├── analyze.sh         # Disk usage explorer wrapper
│   └── status.sh          # System health dashboard wrapper
├── lib/                   # Reusable shell logic
│   ├── core/              # base.sh, log.sh, sudo.sh, ui.sh
│   ├── clean/             # Cleanup modules (user, apps, dev, caches, system)
│   └── ui/                # Confirmation dialogs, progress bars
├── cmd/                   # Go applications
│   ├── analyze/           # Disk analysis tool
│   └── status/            # Real-time monitoring
├── scripts/               # Build and test automation
│   └── test.sh            # Main test runner (shell + go + BATS)
└── tests/                 # BATS integration tests
```

**Decision Tree**:

- User cleanup logic → `lib/clean/<module>.sh`
- Command entry → `bin/<command>.sh`
- Core utils → `lib/core/<util>.sh`
- Performance tool → `cmd/<tool>/*.go`
- Tests → `tests/<test>.bats`

### Language Stack
- **Shell (Bash 3.2)**: Core cleanup and system operations (`lib/`, `bin/`)
- **Go**: Performance-critical tools (`cmd/analyze/`, `cmd/status/`)
- **BATS**: Integration testing (`tests/`)

---

## Code Style Guidelines

### Shell Scripts
- **Indentation**: 4 spaces (configured in .editorconfig)
- **Variables**: `lowercase_with_underscores`
- **Functions**: `verb_noun` format (e.g., `clean_caches`, `get_size`)
- **Constants**: `UPPERCASE_WITH_UNDERSCORES`
- **Quoting**: Always quote variables: `"$var"` not `$var`
- **Tests**: Use `[[` instead of `[`
- **Command substitution**: Use `$(command)` not backticks
- **Error handling**: Use `set -euo pipefail` at top of files

### Go Code
- **Formatting**: Follow standard Go conventions (`gofmt`, `go vet`)
- **Package docs**: Add package-level documentation for exported functions
- **Error handling**: Never ignore errors, always handle them explicitly
- **Build tags**: Use `//go:build darwin` for macOS-specific code

### Comments
- **Language**: English only
- **Focus**: Explain "why" not "what" (code should be self-documenting)
- **Safety**: Document safety boundaries explicitly
- **Non-obvious logic**: Explain workarounds or complex patterns

---

## Key Helper Functions

### Safety Helpers (lib/core/base.sh)
- `safe_rm <path>`: Safe deletion with validation
- `safe_find_delete <base> <pattern> <days> <type>`: Protected find+delete
- `is_protected <path>`: Check if path is system-protected
- `is_whitelisted <name>`: Check user whitelist

### Logging (lib/core/log.sh)
- `log_info <msg>`: Informational messages
- `log_success <msg>`: Success notifications
- `log_warn <msg>`: Warnings
- `log_error <msg>`: Error messages
- `debug <msg>`: Debug output (requires MO_DEBUG=1)

### UI Helpers (lib/core/ui.sh)
- `confirm <prompt>`: Yes/no confirmation
- `show_progress <current> <total> <msg>`: Progress display

---

## Testing Strategy

### Test Types
1. **Syntax Validation**: `bash -n <file>` - catches basic errors
2. **Unit Tests**: BATS tests for individual functions
3. **Integration Tests**: Full command execution with BATS
4. **Dry-run Tests**: `MO_DRY_RUN=1` to validate without deletion
5. **Go Tests**: `go test -v ./cmd/...`

### Test Environment Variables
- `MO_DRY_RUN=1`: Preview changes without execution
- `MO_DEBUG=1`: Enable detailed debug logging
- `BATS_FORMATTER=pretty`: Use pretty output for BATS (default)
- `BATS_FORMATTER=tap`: Use TAP output for CI

---

## Common Development Tasks

### Adding New Cleanup Module
1. Create `lib/clean/new_module.sh`
2. Implement cleanup logic using `safe_*` helpers
3. Source it in `bin/clean.sh`
4. Add protection checks for critical paths
5. Write BATS test in `tests/clean.bats`
6. Test with `MO_DRY_RUN=1` first

### Modifying Go Tools
1. Navigate to `cmd/<tool>/`
2. Make changes to Go files
3. Test with `go run .` or `make build && ./bin/<tool>-go`
4. Run `go test -v` for unit tests
5. Check integration: `./mole <command>`

### Debugging Issues
1. Enable debug mode: `MO_DEBUG=1 ./mole clean`
2. Check logs for error messages
3. Verify sudo permissions: `sudo -n true` or `./mole touchid`
4. Test individual functions in isolation
5. Use `shellcheck` for shell script issues

---

## Linting and Quality

### Shell Script Linting
- **Tool**: shellcheck with custom `.shellcheckrc`
- **Disabled rules**: SC2155, SC2034, SC2059, SC1091, SC2038
- **Command**: `shellcheck --rcfile .shellcheckrc lib/**/*.sh bin/**/*.sh`

### Go Code Quality
- **Tools**: `go vet`, `go fmt`, `go test`
- **Command**: `go vet ./cmd/... && go test ./cmd/...`

### CI/CD Pipeline
- **Triggers**: Push/PR to main, dev branches
- **Platforms**: macOS 14, macOS 15
- **Tools**: bats-core, shellcheck, Go 1.24.6
- **Security checks**: Unsafe rm usage, app protection, secret scanning

---

## File Organization Patterns

### Shell Modules
- Entry scripts in `bin/` should be thin wrappers
- Reusable logic goes in `lib/`
- Core utilities in `lib/core/`
- Feature-specific modules in `lib/clean/`, `lib/ui/`, etc.

### Go Packages
- Each tool in its own `cmd/<tool>/` directory
- Main entry point in `main.go`
- Use standard Go project layout
- macOS-specific code guarded with build tags

---

## GitHub Operations

### Use gh CLI for All GitHub Work

**Preferred Commands**:
```bash
# Issues
gh issue view 123              # View issue details
gh issue list                  # List issues
gh issue comment 123 "message"  # Comment on issue

# Pull Requests
gh pr view                     # View current PR
gh pr diff                     # Show diff
gh pr list                     # List PRs
gh pr checkout 123             # Checkout PR branch
gh pr merge                    # Merge current PR

# Repository operations
gh release create v1.0.0        # Create release
gh repo view                   # Repository info
gh api repos/owner/repo/issues # Raw API access
```

**NEVER use raw git commands for GitHub operations** when `gh` is available:
- ❌ `git log --oneline origin/main..HEAD` → ✅ `gh pr view`
- ❌ `git remote get-url origin` → ✅ `gh repo view`
- ❌ Manual GitHub API curl commands → ✅ `gh api`

## Error Handling Patterns

### Shell Scripts
- Use `set -euo pipefail` for strict error handling
- Check command exit codes: `if command; then ...`
- Provide meaningful error messages with `log_error`
- Use cleanup traps for temporary resources

### Go Code
- Never ignore errors: `if err != nil { return err }`
- Use structured error messages
- Handle context cancellation appropriately
- Log errors with context information

---

## Performance Considerations

### Shell Optimization
- Use built-in shell operations over external commands
- Prefer `find -delete` over `-exec rm`
- Minimize subprocess creation
- Use appropriate timeout mechanisms

### Go Optimization
- Use concurrency for I/O-bound operations
- Implement proper caching for expensive operations
- Profile memory usage in scanning operations
- Use efficient data structures for large datasets

---

## Security Best Practices

### Path Validation
- Always validate user-provided paths
- Check against protection lists before operations
- Use absolute paths to prevent directory traversal
- Implement proper sandboxing for destructive operations

### Permission Management
- Request sudo only when necessary
- Use `sudo -n true` to check sudo availability
- Implement proper Touch ID integration
- Respect user whitelist configurations

---

## Common Pitfalls to Avoid

1. **Over-engineering**: Keep solutions simple. Don't add abstractions for one-time operations.
2. **Premature optimization**: Focus on correctness first, performance second.
3. **Assuming paths exist**: Always check before operating on files/directories.
4. **Ignoring protection logic**: User data loss is unacceptable.
5. **Breaking updates**: Keep `--prefix`/`--config` flags in `install.sh`.
6. **Platform assumptions**: Code must work on all supported macOS versions (10.13+).
7. **Silent failures**: Always log errors and provide actionable messages.

---

## Communication Style

- Be concise and technical
- Explain safety implications upfront
- Show before/after for significant changes
- Provide file:line references for code locations
- Suggest testing steps for validation

---

## Resources

- Main script: `mole` (menu + routing logic)
- Protection lists: Check `is_protected()` implementations
- User config: `~/.config/mole/`
- Test directory: `tests/`
- Build scripts: `scripts/`
- Documentation: `README.md`, `CONTRIBUTING.md`, `SECURITY_AUDIT.md`

---

**Remember**: When in doubt, err on the side of safety. It's better to clean less than to risk user data.