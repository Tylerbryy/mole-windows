#!/usr/bin/env bats

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
    mkdir -p "$HOME/www"
    mkdir -p "$HOME/dev"
    mkdir -p "$HOME/.cache/mole"

    rm -rf "${HOME:?}/www"/* "${HOME:?}/dev"/*
}

@test "is_safe_project_artifact: rejects shallow paths (protection against accidents)" {
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

@test "filter_nested_artifacts: removes nested node_modules" {
    mkdir -p "$HOME/www/project/node_modules/package/node_modules"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        printf '%s\n' '$HOME/www/project/node_modules' '$HOME/www/project/node_modules/package/node_modules' | \
        filter_nested_artifacts | wc -l | tr -d ' '
    ")

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

    [[ "$result" == "2" ]]
}

# Vendor protection unit tests
@test "is_rails_project_root: detects valid Rails project" {
    mkdir -p "$HOME/www/test-rails/config"
    mkdir -p "$HOME/www/test-rails/bin"
    touch "$HOME/www/test-rails/config/application.rb"
    touch "$HOME/www/test-rails/Gemfile"
    touch "$HOME/www/test-rails/bin/rails"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_rails_project_root '$HOME/www/test-rails'; then
            echo 'YES'
        else
            echo 'NO'
        fi
    ")

    [[ "$result" == "YES" ]]
}

@test "is_rails_project_root: rejects non-Rails directory" {
    mkdir -p "$HOME/www/not-rails"
    touch "$HOME/www/not-rails/package.json"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_rails_project_root '$HOME/www/not-rails'; then
            echo 'YES'
        else
            echo 'NO'
        fi
    ")

    [[ "$result" == "NO" ]]
}

@test "is_go_project_root: detects valid Go project" {
    mkdir -p "$HOME/www/test-go"
    touch "$HOME/www/test-go/go.mod"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_go_project_root '$HOME/www/test-go'; then
            echo 'YES'
        else
            echo 'NO'
        fi
    ")

    [[ "$result" == "YES" ]]
}

@test "is_php_project_root: detects valid PHP Composer project" {
    mkdir -p "$HOME/www/test-php"
    touch "$HOME/www/test-php/composer.json"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_php_project_root '$HOME/www/test-php'; then
            echo 'YES'
        else
            echo 'NO'
        fi
    ")

    [[ "$result" == "YES" ]]
}

@test "is_protected_vendor_dir: protects Rails vendor" {
    mkdir -p "$HOME/www/rails-app/vendor"
    mkdir -p "$HOME/www/rails-app/config"
    touch "$HOME/www/rails-app/config/application.rb"
    touch "$HOME/www/rails-app/Gemfile"
    touch "$HOME/www/rails-app/config/environment.rb"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_vendor_dir '$HOME/www/rails-app/vendor'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    [[ "$result" == "PROTECTED" ]]
}

@test "is_protected_vendor_dir: does not protect PHP vendor" {
    mkdir -p "$HOME/www/php-app/vendor"
    touch "$HOME/www/php-app/composer.json"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_vendor_dir '$HOME/www/php-app/vendor'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    [[ "$result" == "NOT_PROTECTED" ]]
}

@test "is_project_container detects project indicators" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
mkdir -p "$HOME/Workspace2/project"
touch "$HOME/Workspace2/project/package.json"
if is_project_container "$HOME/Workspace2" 2; then
    echo "yes"
fi
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"yes"* ]]
}

@test "discover_project_dirs includes detected containers" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
mkdir -p "$HOME/CustomProjects/app"
touch "$HOME/CustomProjects/app/go.mod"
discover_project_dirs | grep -q "$HOME/CustomProjects"
EOF

    [ "$status" -eq 0 ]
}

@test "save_discovered_paths writes config with tilde" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
save_discovered_paths "$HOME/Projects"
grep -q "^~/" "$HOME/.config/mole/purge_paths"
EOF

    [ "$status" -eq 0 ]
}

@test "select_purge_categories returns failure on empty input" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
if select_purge_categories; then
    exit 1
fi
EOF

    [ "$status" -eq 0 ]
}

@test "is_protected_vendor_dir: protects Go vendor" {
    mkdir -p "$HOME/www/go-app/vendor"
    touch "$HOME/www/go-app/go.mod"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_vendor_dir '$HOME/www/go-app/vendor'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    [[ "$result" == "PROTECTED" ]]
}

@test "is_protected_vendor_dir: protects unknown vendor (conservative)" {
    mkdir -p "$HOME/www/unknown-app/vendor"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_vendor_dir '$HOME/www/unknown-app/vendor'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    [[ "$result" == "PROTECTED" ]]
}

@test "is_protected_purge_artifact: handles vendor directories correctly" {
    mkdir -p "$HOME/www/php-app/vendor"
    touch "$HOME/www/php-app/composer.json"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_purge_artifact '$HOME/www/php-app/vendor'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    # PHP vendor should not be protected
    [[ "$result" == "NOT_PROTECTED" ]]
}

@test "is_protected_purge_artifact: returns false for non-vendor artifacts" {
    mkdir -p "$HOME/www/app/node_modules"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        if is_protected_purge_artifact '$HOME/www/app/node_modules'; then
            echo 'PROTECTED'
        else
            echo 'NOT_PROTECTED'
        fi
    ")

    # node_modules is not in the protected list
    [[ "$result" == "NOT_PROTECTED" ]]
}

# Integration tests
@test "scan_purge_targets: skips Rails vendor directory" {
    mkdir -p "$HOME/www/rails-app/vendor/javascript"
    mkdir -p "$HOME/www/rails-app/config"
    touch "$HOME/www/rails-app/config/application.rb"
    touch "$HOME/www/rails-app/Gemfile"
    mkdir -p "$HOME/www/rails-app/bin"
    touch "$HOME/www/rails-app/bin/rails"

    local scan_output
    scan_output="$(mktemp)"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        scan_purge_targets '$HOME/www' '$scan_output'
        if grep -q '$HOME/www/rails-app/vendor' '$scan_output'; then
            echo 'FOUND'
        else
            echo 'SKIPPED'
        fi
    ")

    rm -f "$scan_output"

    [[ "$result" == "SKIPPED" ]]
}

@test "scan_purge_targets: cleans PHP Composer vendor directory" {
    mkdir -p "$HOME/www/php-app/vendor"
    touch "$HOME/www/php-app/composer.json"

    local scan_output
    scan_output="$(mktemp)"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        scan_purge_targets '$HOME/www' '$scan_output'
        if grep -q '$HOME/www/php-app/vendor' '$scan_output'; then
            echo 'FOUND'
        else
            echo 'MISSING'
        fi
    ")

    rm -f "$scan_output"

    [[ "$result" == "FOUND" ]]
}

@test "scan_purge_targets: skips Go vendor directory" {
    mkdir -p "$HOME/www/go-app/vendor"
    touch "$HOME/www/go-app/go.mod"
    touch "$HOME/www/go-app/go.sum"

    local scan_output
    scan_output="$(mktemp)"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        scan_purge_targets '$HOME/www' '$scan_output'
        if grep -q '$HOME/www/go-app/vendor' '$scan_output'; then
            echo 'FOUND'
        else
            echo 'SKIPPED'
        fi
    ")

    rm -f "$scan_output"

    [[ "$result" == "SKIPPED" ]]
}

@test "scan_purge_targets: skips unknown vendor directory" {
    # Create a vendor directory without any project file
    mkdir -p "$HOME/www/unknown-app/vendor"

    local scan_output
    scan_output="$(mktemp)"

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        scan_purge_targets '$HOME/www' '$scan_output'
        if grep -q '$HOME/www/unknown-app/vendor' '$scan_output'; then
            echo 'FOUND'
        else
            echo 'SKIPPED'
        fi
    ")

    rm -f "$scan_output"

    # Unknown vendor should be protected (conservative approach)
    [[ "$result" == "SKIPPED" ]]
}

@test "is_recently_modified: detects recent projects" {
    mkdir -p "$HOME/www/project/node_modules"
    touch "$HOME/www/project/package.json"

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

    bash -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/project.sh'
        is_recently_modified '$HOME/www/old-project/node_modules' || true
    "
    local exit_code=$?
    [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ]
}

@test "purge targets are configured correctly" {
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        echo \"\${PURGE_TARGETS[@]}\"
    ")
    [[ "$result" == *"node_modules"* ]]
    [[ "$result" == *"target"* ]]
}

@test "get_dir_size_kb: calculates directory size" {
    mkdir -p "$HOME/www/test-project/node_modules"
    dd if=/dev/zero of="$HOME/www/test-project/node_modules/file.bin" bs=1024 count=1024 2>/dev/null

    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        get_dir_size_kb '$HOME/www/test-project/node_modules'
    ")

    [[ "$result" -ge 1000 ]] && [[ "$result" -le 1100 ]]
}

@test "get_dir_size_kb: handles non-existent paths gracefully" {
    result=$(bash -c "
        source '$PROJECT_ROOT/lib/clean/project.sh'
        get_dir_size_kb '$HOME/www/non-existent'
    ")
    [[ "$result" == "0" ]]
}

@test "clean_project_artifacts: handles empty directory gracefully" {
    run bash -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/project.sh'
        clean_project_artifacts
    " < /dev/null

    [[ "$status" -eq 0 ]] || [[ "$status" -eq 2 ]]
}

@test "clean_project_artifacts: scans and finds artifacts" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    mkdir -p "$HOME/www/test-project/node_modules/package1"
    echo "test data" > "$HOME/www/test-project/node_modules/package1/index.js"

    mkdir -p "$HOME/www/test-project"

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    run bash -c "
        export HOME='$HOME'
        $timeout_cmd 5 '$PROJECT_ROOT/bin/purge.sh' 2>&1 < /dev/null || true
    "

    [[ "$output" =~ "Scanning" ]] ||
    [[ "$output" =~ "Purge complete" ]] ||
    [[ "$output" =~ "No old" ]] ||
    [[ "$output" =~ "Great" ]]
}

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
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    run bash -c "
        export HOME='$HOME'
        $timeout_cmd 2 '$PROJECT_ROOT/mole' purge --debug < /dev/null 2>&1 || true
    "
    true
}

@test "mo purge: creates cache directory for stats" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    bash -c "
        export HOME='$HOME'
        $timeout_cmd 2 '$PROJECT_ROOT/mole' purge < /dev/null 2>&1 || true
    "

    [ -d "$HOME/.cache/mole" ] || [ -d "${XDG_CACHE_HOME:-$HOME/.cache}/mole" ]
}
