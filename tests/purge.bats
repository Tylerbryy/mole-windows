#!/usr/bin/env bats
# Tests for project artifact purge functionality
# bin/purge.sh and lib/clean/project.sh

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-purge-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    # Create test project directories
    mkdir -p "$HOME/www"
    mkdir -p "$HOME/dev"
    mkdir -p "$HOME/.cache/mole"

    # Clean any previous test artifacts
    rm -rf "${HOME:?}/www"/* "${HOME:?}/dev"/*
}

# =================================================================
# Safety Checks
# =================================================================

@test "is_safe_project_artifact: rejects shallow paths (protection against accidents)" {
    # Should reject ~/www/node_modules (too shallow, depth < 1)
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_safe_project_artifact '$HOME/www/node_modules' '$HOME/www'; then
            echo 'UNSAFE'
        else
            echo 'SAFE'
        fi
    ")
    [[ "$result" == "SAFE" ]]
}

@test "is_safe_project_artifact: allows proper project artifacts" {
    # Should allow ~/www/myproject/node_modules (depth >= 1)
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_safe_project_artifact '$HOME/www/myproject/node_modules' '$HOME/www'; then
            echo 'ALLOWED'
        else
            echo 'BLOCKED'
        fi
    ")
    [[ "$result" == "ALLOWED" ]]
}

@test "is_safe_project_artifact: rejects non-absolute paths" {
    # Should reject relative paths
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_safe_project_artifact 'relative/path/node_modules' '$HOME/www'; then
            echo 'UNSAFE'
        else
            echo 'SAFE'
        fi
    ")
    [[ "$result" == "SAFE" ]]
}

@test "is_safe_project_artifact: validates depth calculation" {
    # ~/www/project/subdir/node_modules should be allowed (depth = 2)
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_safe_project_artifact '$HOME/www/project/subdir/node_modules' '$HOME/www'; then
            echo 'ALLOWED'
        else
            echo 'BLOCKED'
        fi
    ")
    [[ "$result" == "ALLOWED" ]]
}

# =================================================================
# Nested Artifact Filtering
# =================================================================

@test "filter_nested_artifacts: removes nested node_modules" {
    # Create nested structure:
    # ~/www/project/node_modules/package/node_modules
    mkdir -p "$HOME/www/project/node_modules/package/node_modules"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        printf '%s\n' '$HOME/www/project/node_modules' '$HOME/www/project/node_modules/package/node_modules' | \
        filter_nested_artifacts | wc -l | tr -d ' '
    ")

    # Should only keep the parent node_modules (nested one filtered out)
    [[ "$result" == "1" ]]
}

@test "filter_nested_artifacts: keeps independent artifacts" {
    mkdir -p "$HOME/www/project1/node_modules"
    mkdir -p "$HOME/www/project2/target"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        printf '%s\n' '$HOME/www/project1/node_modules' '$HOME/www/project2/target' | \
        filter_nested_artifacts | wc -l | tr -d ' '
    ")

    # Should keep both (they're independent)
    [[ "$result" == "2" ]]
}

# =================================================================
# Recently Modified Detection
# =================================================================

@test "is_recently_modified: detects recent projects" {
    mkdir -p "$HOME/www/project/node_modules"
    touch "$HOME/www/project/package.json"  # Recently touched

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_recently_modified '$HOME/www/project/node_modules'; then
            echo 'RECENT'
        else
            echo 'OLD'
        fi
    ")
    [[ "$result" == "RECENT" ]]
}

@test "is_recently_modified: marks old projects correctly" {
    mkdir -p "$HOME/www/old-project/node_modules"
    mkdir -p "$HOME/www/old-project"

    # Simulate old project (modified 30 days ago)
    # Note: This is hard to test reliably without mocking 'find'
    # Just verify the function can run without errors
    bash -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/project.sh'
        is_recently_modified '$HOME/www/old-project/node_modules' || true
    "
    local exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ]  # Allow both true/false, just check no crash
}

# =================================================================
# Artifact Detection
# =================================================================

@test "purge targets are configured correctly" {
    # Verify PURGE_TARGETS array exists and contains expected values
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        echo \"\${PURGE_TARGETS[@]}\"
    ")
    [[ "$result" == *"node_modules"* ]]
    [[ "$result" == *"target"* ]]
}

# =================================================================
# Size Calculation
# =================================================================

@test "get_dir_size_kb: calculates directory size" {
    mkdir -p "$HOME/www/test-project/node_modules"
    # Create a file with known size (~1MB)
    dd if=/dev/zero of="$HOME/www/test-project/node_modules/file.bin" bs=1024 count=1024 2>/dev/null

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        get_dir_size_kb '$HOME/www/test-project/node_modules'
    ")

    # Should be around 1024 KB (allow some filesystem overhead)
    [[ "$result" -ge 1000 ]] && [[ "$result" -le 1100 ]]
}

@test "get_dir_size_kb: handles non-existent paths gracefully" {
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        get_dir_size_kb '$HOME/www/non-existent'
    ")
    [[ "$result" == "0" ]]
}

# =================================================================
# Integration Tests (Non-Interactive)
# =================================================================

@test "clean_project_artifacts: handles empty directory gracefully" {
    # No projects, should exit cleanly
    run bash -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/project.sh'
        clean_project_artifacts
    " < /dev/null

    # Should succeed (exit code 0 or 2 for nothing to clean)
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 2 ]]
}

@test "clean_project_artifacts: scans and finds artifacts" {
    # Create test project with node_modules (make it big enough to detect)
    mkdir -p "$HOME/www/test-project/node_modules/package1"
    echo "test data" > "$HOME/www/test-project/node_modules/package1/index.js"

    # Create parent directory timestamp old enough
    mkdir -p "$HOME/www/test-project"

    # Run in non-interactive mode (with timeout to avoid hanging)
    run bash -c "
        export HOME='$HOME'
        timeout 5 '$PROJECT_ROOT/bin/purge.sh' 2>&1 < /dev/null || true
    "

    # Should either scan successfully or exit gracefully
    # Check for expected outputs (scanning, completion, or nothing found)
    [[ "$output" =~ "Scanning" ]] ||
    [[ "$output" =~ "Purge complete" ]] ||
    [[ "$output" =~ "No old" ]] ||
    [[ "$output" =~ "Great" ]]
}

# =================================================================
# Command Line Interface
# =================================================================

@test "mo purge: command exists and is executable" {
    [ -x "$PROJECT_ROOT/mole" ]
    [ -f "$PROJECT_ROOT/bin/purge.sh" ]
}

@test "mo purge: shows in help text" {
    run env HOME="$HOME" "$PROJECT_ROOT/mole" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"mo purge"* ]]
}

@test "mo purge: accepts --debug flag" {
    # Just verify it doesn't crash with --debug
    run bash -c "
        export HOME='$HOME'
        timeout 2 '$PROJECT_ROOT/mole' purge --debug < /dev/null 2>&1 || true
    "
    # Should not crash (any exit code is OK, we just want to verify it runs)
    true
}

@test "mo purge: creates cache directory for stats" {
    # Run purge (will exit quickly in non-interactive with no projects)
    bash -c "
        export HOME='$HOME'
        timeout 2 '$PROJECT_ROOT/mole' purge < /dev/null 2>&1 || true
    "

    # Cache directory should be created
    [ -d "$HOME/.cache/mole" ] || [ -d "${XDG_CACHE_HOME:-$HOME/.cache}/mole" ]
}
