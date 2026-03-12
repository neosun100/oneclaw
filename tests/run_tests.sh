#!/bin/bash
# ============================================================================
# OneClaw Test Suite — Validates all scripts via syntax, logic, and regression
# Usage: bash tests/run_tests.sh
# ============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; SKIP=$((SKIP+1)); }
section() { echo -e "\n${CYAN}${BOLD}[$1]${NC}"; }

# ============================================================================
section "1. Bash Syntax Validation"
# ============================================================================

for script in setup.sh install-linux.sh fix.sh; do
    if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
        pass "$script — syntax OK"
    else
        fail "$script — syntax error"
        bash -n "$SCRIPT_DIR/$script" 2>&1 | head -5
    fi
done

# ============================================================================
section "2. ShellCheck Static Analysis"
# ============================================================================

if command -v shellcheck >/dev/null 2>&1; then
    for script in setup.sh install-linux.sh fix.sh; do
        # SC2034=unused vars (expected in config scripts), SC1091=sourced files, SC2086=word splitting (intentional in some places)
        ISSUES=$(shellcheck -S warning -e SC2034,SC1091,SC2086,SC2129,SC2016,SC2046,SC2015,SC2181 "$SCRIPT_DIR/$script" 2>&1 | grep -c "^In " || true)
        if [ "$ISSUES" -eq 0 ]; then
            pass "$script — shellcheck clean"
        else
            fail "$script — shellcheck found $ISSUES warning(s)"
            shellcheck -S warning -e SC2034,SC1091,SC2086,SC2129,SC2016,SC2046,SC2015,SC2181 "$SCRIPT_DIR/$script" 2>&1 | head -20
        fi
    done
else
    skip "shellcheck not installed — install with: apt install shellcheck"
fi

# ============================================================================
section "3. setup.sh — Multi-Auth Menu Presence"
# ============================================================================

grep -q 'AWS_AUTH_MODE="static-keys"' "$SCRIPT_DIR/setup.sh" && pass "Auth mode: static-keys defined" || fail "Auth mode: static-keys missing"
grep -q 'AWS_AUTH_MODE="sso"' "$SCRIPT_DIR/setup.sh" && pass "Auth mode: sso defined" || fail "Auth mode: sso missing"
grep -q 'AWS_AUTH_MODE="profile"' "$SCRIPT_DIR/setup.sh" && pass "Auth mode: profile defined" || fail "Auth mode: profile missing"
grep -q 'AWS_AUTH_MODE="skip"' "$SCRIPT_DIR/setup.sh" && pass "Auth mode: skip defined" || fail "Auth mode: skip missing"

# ============================================================================
section "4. setup.sh — SSO Configuration"
# ============================================================================

grep -q 'sso_start_url' "$SCRIPT_DIR/setup.sh" && pass "SSO: sso_start_url written to config" || fail "SSO: sso_start_url missing"
grep -q 'sso_region' "$SCRIPT_DIR/setup.sh" && pass "SSO: sso_region written to config" || fail "SSO: sso_region missing"
grep -q 'sso_account_id' "$SCRIPT_DIR/setup.sh" && pass "SSO: sso_account_id written to config" || fail "SSO: sso_account_id missing"
grep -q 'sso_role_name' "$SCRIPT_DIR/setup.sh" && pass "SSO: sso_role_name written to config" || fail "SSO: sso_role_name missing"
grep -q 'CLAUDE_CODE_AWS_AUTH_REFRESH' "$SCRIPT_DIR/setup.sh" && pass "SSO: CLAUDE_CODE_AWS_AUTH_REFRESH set" || fail "SSO: auth refresh missing"
grep -q 'aws sso login' "$SCRIPT_DIR/setup.sh" && pass "SSO: aws sso login triggered" || fail "SSO: login trigger missing"

# ============================================================================
section "5. setup.sh — Profile Support"
# ============================================================================

grep -q 'AWS_PROFILE_NAME' "$SCRIPT_DIR/setup.sh" && pass "Profile: AWS_PROFILE_NAME variable used" || fail "Profile: variable missing"
grep -q 'AWS_PROFILE' "$SCRIPT_DIR/setup.sh" && pass "Profile: AWS_PROFILE exported" || fail "Profile: export missing"
grep -q 'AWS_VERIFY_ARGS' "$SCRIPT_DIR/setup.sh" && pass "Profile: verification uses profile args" || fail "Profile: verify args missing"
grep -q 'BEDROCK_VERIFY_ARGS' "$SCRIPT_DIR/setup.sh" && pass "Profile: Bedrock verify uses profile" || fail "Profile: Bedrock verify missing"

# ============================================================================
section "6. setup.sh — Region Prefix Logic"
# ============================================================================

# Test that all 3 region prefixes are handled
grep -q 'eu-\*).*PROFILE_PREFIX="eu"' "$SCRIPT_DIR/setup.sh" && pass "Region: eu prefix handled" || fail "Region: eu prefix missing"
grep -q 'ap-\*).*PROFILE_PREFIX="ap"' "$SCRIPT_DIR/setup.sh" && pass "Region: ap prefix handled" || fail "Region: ap prefix missing"

# ============================================================================
section "7. setup.sh — No 'local' Outside Functions"
# ============================================================================

# Extract lines with 'local' that are NOT inside function bodies
# This is a simplified check: 'local' should only appear after a function opening
BAD_LOCALS=$(awk '
    /^[a-zA-Z_].*\(\)/ { in_func=1 }
    /^}/ { in_func=0 }
    /^\s*local / && !in_func { print NR": "$0 }
' "$SCRIPT_DIR/setup.sh" || true)

if [ -z "$BAD_LOCALS" ]; then
    pass "No 'local' keyword used outside functions"
else
    fail "'local' used outside function context:"
    echo "$BAD_LOCALS"
fi

# ============================================================================
section "8. setup.sh — SSO_LOGIN_PENDING Initialized"
# ============================================================================

grep -q 'SSO_LOGIN_PENDING=false' "$SCRIPT_DIR/setup.sh" && pass "SSO_LOGIN_PENDING initialized before use" || fail "SSO_LOGIN_PENDING not initialized (set -u will fail)"

# ============================================================================
section "9. setup.sh — Shell RC Writes Both Files"
# ============================================================================

grep -q 'BASHRC=' "$SCRIPT_DIR/setup.sh" && pass "Shell RC: BASHRC variable defined" || fail "Shell RC: BASHRC missing"
grep -q 'add_to_rc' "$SCRIPT_DIR/setup.sh" && pass "Shell RC: add_to_rc function used" || fail "Shell RC: add_to_rc missing"

# ============================================================================
section "10. install-linux.sh — Platform Detection"
# ============================================================================

grep -q 'detect_pkg_manager' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: package manager detection" || fail "Linux: pkg detection missing"
grep -q 'apt' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: apt support" || fail "Linux: apt missing"
grep -q 'dnf' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: dnf support" || fail "Linux: dnf missing"
grep -q 'pacman' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: pacman support" || fail "Linux: pacman missing"

# ============================================================================
section "11. install-linux.sh — systemd Services"
# ============================================================================

grep -q 'openclaw-gateway.service' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: gateway systemd service" || fail "Linux: gateway service missing"
grep -q 'openclaw-node.service' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: node systemd service" || fail "Linux: node service missing"
grep -q 'openclaw-chrome.service' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: chrome systemd service" || fail "Linux: chrome service missing"
grep -q 'openclaw-guardian.timer' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: guardian timer" || fail "Linux: guardian timer missing"
grep -q 'enable-linger' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: loginctl enable-linger" || fail "Linux: linger missing"

# ============================================================================
section "12. install-linux.sh — Multi-Auth"
# ============================================================================

grep -q 'AUTH_CHOICE' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: auth choice menu" || fail "Linux: auth menu missing"
grep -q 'sso_start_url' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: SSO config support" || fail "Linux: SSO missing"
grep -q 'CLAUDE_CODE_AWS_AUTH_REFRESH' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: SSO auth refresh" || fail "Linux: SSO refresh missing"

# ============================================================================
section "13. install-linux.sh — Architecture Detection"
# ============================================================================

grep -q 'aarch64' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: aarch64 AWS CLI" || fail "Linux: aarch64 missing"
grep -q 'x86_64' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: x86_64 AWS CLI" || fail "Linux: x86_64 missing"

# ============================================================================
section "14. fix.sh — SSO Detection"
# ============================================================================

grep -q 'SSO_PROFILE' "$SCRIPT_DIR/fix.sh" && pass "Fix: SSO profile detection" || fail "Fix: SSO detection missing"
grep -q 'aws sso login' "$SCRIPT_DIR/fix.sh" && pass "Fix: SSO login suggestion" || fail "Fix: SSO login hint missing"

# ============================================================================
section "15. docker-compose.yml — Validation"
# ============================================================================

if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    pass "docker-compose.yml exists"
    grep -q '18789' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: gateway port mapped" || fail "Docker: port missing"
    grep -q '9222' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: chrome CDP port mapped" || fail "Docker: CDP port missing"
    grep -q '127.0.0.1' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: ports bound to localhost" || fail "Docker: ports not localhost-bound"
    grep -q 'healthcheck' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: healthcheck defined" || fail "Docker: healthcheck missing"
    grep -q '.aws:/root/.aws:ro' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: AWS creds mounted read-only" || fail "Docker: AWS mount missing/not ro"
else
    fail "docker-compose.yml not found"
fi

# ============================================================================
section "16. README Consistency"
# ============================================================================

for readme in README.md README.zh.md; do
    if [ -f "$SCRIPT_DIR/$readme" ]; then
        grep -q 'install-linux.sh' "$SCRIPT_DIR/$readme" && pass "$readme: Linux install link" || fail "$readme: Linux link missing"
        grep -q 'docker compose' "$SCRIPT_DIR/$readme" && pass "$readme: Docker instructions" || fail "$readme: Docker missing"
        grep -q 'SSO' "$SCRIPT_DIR/$readme" && pass "$readme: SSO documentation" || fail "$readme: SSO docs missing"
        grep -q 'systemd' "$SCRIPT_DIR/$readme" && pass "$readme: Linux systemd docs" || fail "$readme: systemd docs missing"
    else
        fail "$readme not found"
    fi
done

# ============================================================================
section "17. Skills — SKILL.md Presence"
# ============================================================================

for skill in claude-code aws-infra chrome-devtools skill-vetting architecture-svg; do
    if [ -f "$SCRIPT_DIR/skills/$skill/SKILL.md" ]; then
        pass "Skill $skill: SKILL.md exists"
        # Check YAML frontmatter
        head -1 "$SCRIPT_DIR/skills/$skill/SKILL.md" | grep -q '^---' && pass "Skill $skill: has YAML frontmatter" || fail "Skill $skill: missing frontmatter"
    else
        fail "Skill $skill: SKILL.md missing"
    fi
done

# ============================================================================
section "18. Security Scanner — Syntax"
# ============================================================================

if command -v python3 >/dev/null 2>&1; then
    python3 -c "import py_compile; py_compile.compile('$SCRIPT_DIR/skills/skill-vetting/scripts/scan.py', doraise=True)" 2>/dev/null \
        && pass "scan.py — Python syntax OK" \
        || fail "scan.py — Python syntax error"
    
    # Test scanner runs without error on the skills directory itself
    SCAN_EXIT=0
    python3 "$SCRIPT_DIR/skills/skill-vetting/scripts/scan.py" "$SCRIPT_DIR/skills/claude-code" --format json > /tmp/oneclaw-scan-test.json 2>/dev/null || SCAN_EXIT=$?
    if [ "$SCAN_EXIT" -le 1 ]; then
        pass "scan.py — runs successfully on test input"
    else
        fail "scan.py — runtime error"
    fi
else
    skip "python3 not available"
fi

# ============================================================================
section "19. Guardian Script — Logic Validation"
# ============================================================================

# The guardian script is embedded in setup.sh as a heredoc. Extract and validate.
GUARDIAN="$SCRIPT_DIR/skills/../tests/.guardian-extracted.sh"
sed -n "/^cat > .*guardian-check.sh.*<<'GUARDIAN_EOF'/,/^GUARDIAN_EOF/p" "$SCRIPT_DIR/setup.sh" | sed '1d;$d' > "$GUARDIAN" 2>/dev/null

if [ -s "$GUARDIAN" ]; then
    bash -n "$GUARDIAN" 2>/dev/null && pass "Guardian script: syntax OK" || fail "Guardian script: syntax error"
    grep -q 'MAX_REPAIR=3' "$GUARDIAN" && pass "Guardian: max repair limit" || fail "Guardian: no repair limit"
    grep -q 'COOLDOWN_SECONDS=300' "$GUARDIAN" && pass "Guardian: cooldown period" || fail "Guardian: no cooldown"
    grep -q 'check_process' "$GUARDIAN" && pass "Guardian: process check layer" || fail "Guardian: process check missing"
    grep -q 'check_http' "$GUARDIAN" && pass "Guardian: HTTP check layer" || fail "Guardian: HTTP check missing"
    grep -q 'check_status' "$GUARDIAN" && pass "Guardian: status check layer" || fail "Guardian: status check missing"
    grep -q 'DISCORD_WEBHOOK' "$GUARDIAN" && pass "Guardian: Discord notification" || fail "Guardian: Discord missing"
    rm -f "$GUARDIAN"
else
    fail "Guardian script: could not extract from setup.sh"
fi

# ============================================================================
section "20. Regression — No Hardcoded Secrets"
# ============================================================================

for f in setup.sh install-linux.sh fix.sh docker-compose.yml; do
    if grep -qiE '(AKIA[A-Z0-9]{16}|sk-[a-zA-Z0-9]{48}|ghp_[a-zA-Z0-9]{36})' "$SCRIPT_DIR/$f" 2>/dev/null; then
        fail "$f: contains hardcoded secret pattern!"
    else
        pass "$f: no hardcoded secrets"
    fi
done

# ============================================================================
section "21. Regression — All Ports Bind Localhost"
# ============================================================================

# Check that services only bind to 127.0.0.1 / loopback
grep -q '"bind": "loopback"' "$SCRIPT_DIR/setup.sh" && pass "setup.sh: gateway binds loopback" || fail "setup.sh: gateway not loopback"
grep -q '127.0.0.1' "$SCRIPT_DIR/install-linux.sh" && pass "install-linux.sh: node binds 127.0.0.1" || fail "install-linux.sh: node not localhost"

# ============================================================================

# ============================================================================
section "22. TODO 1 — WSL2 Detection"
# ============================================================================

grep -q 'IS_WSL' "$SCRIPT_DIR/install-linux.sh" && pass "WSL: IS_WSL variable" || fail "WSL: IS_WSL missing"
grep -q 'microsoft' "$SCRIPT_DIR/install-linux.sh" && pass "WSL: proc check" || fail "WSL: proc missing"
grep -q 'SKIP_SYSTEMD' "$SCRIPT_DIR/install-linux.sh" && pass "WSL: SKIP_SYSTEMD guard" || fail "WSL: guard missing"
grep -q 'pidof systemd' "$SCRIPT_DIR/install-linux.sh" && pass "WSL: systemd runtime check" || fail "WSL: runtime missing"

# ============================================================================
section "23. TODO 2 — Log Rotation"
# ============================================================================

grep -q 'rotate-logs.sh' "$SCRIPT_DIR/setup.sh" && pass "LogRotate macOS: script" || fail "LogRotate macOS: missing"
grep -q 'MAX_SIZE' "$SCRIPT_DIR/setup.sh" && pass "LogRotate macOS: size limit" || fail "LogRotate macOS: no limit"
grep -q 'logrotate.conf' "$SCRIPT_DIR/install-linux.sh" && pass "LogRotate Linux: config" || fail "LogRotate Linux: missing"
grep -q 'crontab' "$SCRIPT_DIR/install-linux.sh" && pass "LogRotate Linux: cron" || fail "LogRotate Linux: no cron"
grep -q 'copytruncate' "$SCRIPT_DIR/install-linux.sh" && pass "LogRotate Linux: copytruncate" || fail "LogRotate Linux: unsafe"

# ============================================================================
section "24. TODO 3 — i18n Auto-Detection"
# ============================================================================

grep -q 'USE_ZH' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: USE_ZH var" || fail "i18n: USE_ZH missing"
grep -q 'msg_auth_prompt' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: auth prompt fn" || fail "i18n: auth fn missing"
grep -q 'msg_region_prompt' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: region prompt fn" || fail "i18n: region fn missing"
grep -q 'msg_install_done' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: done msg fn" || fail "i18n: done fn missing"
grep -q '$(msg_auth_prompt)' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: auth prompt CALLED" || fail "i18n: auth NOT called"
grep -q '$(msg_region_prompt)' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: region prompt CALLED" || fail "i18n: region NOT called"
grep -q '$(msg_install_done)' "$SCRIPT_DIR/install-linux.sh" && pass "i18n: done msg CALLED" || fail "i18n: done NOT called"

# ============================================================================
section "25. TODO 4 — Progress Spinner"
# ============================================================================

grep -q 'spin()' "$SCRIPT_DIR/install-linux.sh" && pass "Spinner: function defined" || fail "Spinner: missing"
grep -q 'kill -0' "$SCRIPT_DIR/install-linux.sh" && pass "Spinner: process loop" || fail "Spinner: no loop"

# ============================================================================
section "26. TODO 5 — Backup/Restore"
# ============================================================================

if [ -f "$SCRIPT_DIR/backup-restore.sh" ]; then
    pass "backup-restore.sh exists"
    bash -n "$SCRIPT_DIR/backup-restore.sh" 2>/dev/null && pass "backup-restore.sh syntax OK" || fail "backup-restore.sh syntax error"
    grep -q 'do_backup' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: backup fn" || fail "Backup: fn missing"
    grep -q 'do_restore' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: restore fn" || fail "Backup: fn missing"
    grep -q 'do_list' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: list fn" || fail "Backup: fn missing"
    grep -q '\.aws' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: AWS creds" || fail "Backup: no AWS"
    grep -q 'openclaw.json' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: OC config" || fail "Backup: no config"
    grep -q 'settings.json' "$SCRIPT_DIR/backup-restore.sh" && pass "Backup: Claude cfg" || fail "Backup: no Claude"
    HELP_OUT=$(bash "$SCRIPT_DIR/backup-restore.sh" 2>&1 || true)
    echo "$HELP_OUT" | grep -q 'backup' && pass "Backup: help works" || fail "Backup: help broken"
else
    fail "backup-restore.sh not found"
fi

# ============================================================================
section "27. Regression — All Scripts Syntax (final)"
# ============================================================================

for script in setup.sh install-linux.sh fix.sh backup-restore.sh; do
    [ -f "$SCRIPT_DIR/$script" ] || continue
    bash -n "$SCRIPT_DIR/$script" 2>/dev/null && pass "$script: final syntax OK" || fail "$script: BROKEN"
done

# ============================================================================
section "28. setup.sh — Embedded Scripts Syntax"
# ============================================================================

# Extract and validate repair.sh heredoc
REPAIR_TMP=$(mktemp)
sed -n "/^cat > .*scripts\/repair.sh.*<<'REPAIR_EOF'/,/^REPAIR_EOF/p" "$SCRIPT_DIR/setup.sh" | sed '1d;$d' > "$REPAIR_TMP" 2>/dev/null
if [ -s "$REPAIR_TMP" ]; then
    bash -n "$REPAIR_TMP" 2>/dev/null && pass "Embedded repair.sh: syntax OK" || fail "Embedded repair.sh: syntax error"
else
    fail "Embedded repair.sh: could not extract"
fi
rm -f "$REPAIR_TMP"

# Extract and validate ai-repair.sh heredoc
AIREPAIR_TMP=$(mktemp)
sed -n "/^cat > .*scripts\/ai-repair.sh.*<<'AIREPAIR_EOF'/,/^AIREPAIR_EOF/p" "$SCRIPT_DIR/setup.sh" | sed '1d;$d' > "$AIREPAIR_TMP" 2>/dev/null
if [ -s "$AIREPAIR_TMP" ]; then
    bash -n "$AIREPAIR_TMP" 2>/dev/null && pass "Embedded ai-repair.sh: syntax OK" || fail "Embedded ai-repair.sh: syntax error"
else
    fail "Embedded ai-repair.sh: could not extract"
fi
rm -f "$AIREPAIR_TMP"

# Extract and validate open-claude.command heredoc
OC_TMP=$(mktemp)
sed -n "/^cat > .*open-claude.command.*<<'ASKCLAUDE_EOF'/,/^ASKCLAUDE_EOF/p" "$SCRIPT_DIR/setup.sh" | sed '1d;$d' > "$OC_TMP" 2>/dev/null
if [ -s "$OC_TMP" ]; then
    bash -n "$OC_TMP" 2>/dev/null && pass "Embedded open-claude.command: syntax OK" || fail "Embedded open-claude.command: syntax error"
else
    fail "Embedded open-claude.command: could not extract"
fi
rm -f "$OC_TMP"

# ============================================================================
section "29. setup.sh — LaunchAgent Helpers"
# ============================================================================

grep -q 'la_load()' "$SCRIPT_DIR/setup.sh" && pass "la_load function defined" || fail "la_load missing"
grep -q 'la_unload()' "$SCRIPT_DIR/setup.sh" && pass "la_unload function defined" || fail "la_unload missing"
grep -q '_launchctl_has_bootstrap()' "$SCRIPT_DIR/setup.sh" && pass "_launchctl_has_bootstrap defined" || fail "bootstrap helper missing"
grep -q 'sw_vers.*productVersion' "$SCRIPT_DIR/setup.sh" && pass "macOS version detection" || fail "version detection missing"
grep -q 'gui/${GUI_UID}' "$SCRIPT_DIR/setup.sh" && pass "GUI UID used in launchctl" || fail "GUI UID missing"

# ============================================================================
section "30. setup.sh — Input Functions"
# ============================================================================

grep -q 'ask_secret()' "$SCRIPT_DIR/setup.sh" && pass "ask_secret function defined" || fail "ask_secret missing"
grep -q 'ask_optional()' "$SCRIPT_DIR/setup.sh" && pass "ask_optional function defined" || fail "ask_optional missing"
grep -q 'read -rs' "$SCRIPT_DIR/setup.sh" && pass "ask_secret hides input (-s flag)" || fail "secret input not hidden"
grep -q '/dev/tty' "$SCRIPT_DIR/setup.sh" && pass "Input reads from /dev/tty (pipe-safe)" || fail "no /dev/tty"

# ============================================================================
section "31. setup.sh — Chinese Symlinks"
# ============================================================================

grep -q '一键修复.command' "$SCRIPT_DIR/setup.sh" && pass "Chinese symlink: 一键修复" || fail "一键修复 missing"
grep -q 'AI修复.command' "$SCRIPT_DIR/setup.sh" && pass "Chinese symlink: AI修复" || fail "AI修复 missing"
grep -q '打开Claude对话.command' "$SCRIPT_DIR/setup.sh" && pass "Chinese symlink: 打开Claude对话" || fail "打开Claude对话 missing"
grep -q 'ln -sf' "$SCRIPT_DIR/setup.sh" && pass "Symlinks use ln -sf (force)" || fail "symlinks not forced"

# ============================================================================
section "32. setup.sh — Generated Config JSON Validity"
# ============================================================================

# Extract the openclaw.json template and validate structure
grep -q '"gateway"' "$SCRIPT_DIR/setup.sh" && pass "OC config: gateway section" || fail "OC config: no gateway"
grep -q '"models"' "$SCRIPT_DIR/setup.sh" && pass "OC config: models section" || fail "OC config: no models"
grep -q '"agents"' "$SCRIPT_DIR/setup.sh" && pass "OC config: agents section" || fail "OC config: no agents"
grep -q '"browser"' "$SCRIPT_DIR/setup.sh" && pass "OC config: browser section" || fail "OC config: no browser"
grep -q 'bedrock-converse-stream' "$SCRIPT_DIR/setup.sh" && pass "OC config: bedrock API type" || fail "OC config: wrong API"

# Claude Code settings.json structure
grep -q 'CLAUDE_CODE_USE_BEDROCK' "$SCRIPT_DIR/setup.sh" && pass "Claude cfg: BEDROCK flag" || fail "Claude cfg: no BEDROCK"
grep -q 'ANTHROPIC_MODEL' "$SCRIPT_DIR/setup.sh" && pass "Claude cfg: model set" || fail "Claude cfg: no model"
grep -q '"deny"' "$SCRIPT_DIR/setup.sh" && pass "Claude cfg: deny list (safety)" || fail "Claude cfg: no deny list"
grep -q 'rm -rf /\*' "$SCRIPT_DIR/setup.sh" && pass "Claude cfg: blocks rm -rf /*" || fail "Claude cfg: rm not blocked"

# ============================================================================
section "33. setup.sh — CLAUDE.md Generation"
# ============================================================================

grep -q 'CLAUDE.md' "$SCRIPT_DIR/setup.sh" && pass "CLAUDE.md generated" || fail "CLAUDE.md missing"
grep -q 'OpenClaw Workspace' "$SCRIPT_DIR/setup.sh" && pass "CLAUDE.md has workspace header" || fail "CLAUDE.md no header"
grep -q '127.0.0.1:18789' "$SCRIPT_DIR/setup.sh" && pass "CLAUDE.md references control UI" || fail "CLAUDE.md no UI ref"

# ============================================================================
section "34. fix.sh — Token Fix Logic"
# ============================================================================

grep -q 'python3 -c' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: uses python3 for JSON" || fail "fix.sh: no python3"
grep -q 'BROKEN_JSON' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: handles broken JSON" || fail "fix.sh: no broken JSON handling"
grep -q 'FIXED' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: FIXED status path" || fail "fix.sh: no FIXED path"
grep -q 'OK:' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: OK status path" || fail "fix.sh: no OK path"
grep -q 'openssl rand' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: generates new token" || fail "fix.sh: no token gen"

# ============================================================================
section "35. fix.sh — Plist Entrypoint Fix"
# ============================================================================

grep -q 'ACTUAL_OPENCLAW' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: detects actual binary path" || fail "fix.sh: no path detection"
grep -q 'FIXED_PLISTS' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: tracks fixed plists" || fail "fix.sh: no fix tracking"
grep -q 'plistlib' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: uses plistlib for safe edit" || fail "fix.sh: no plistlib"
grep -q 'ProgramArguments' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: fixes ProgramArguments[0]" || fail "fix.sh: no arg fix"

# ============================================================================
section "36. fix.sh — Embedded Repair Scripts"
# ============================================================================

grep -q 'dangerously-skip-permissions' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: AI repair uses skip-perms" || fail "fix.sh: no skip-perms"
grep -q 'NEED_RESTORE' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: auto-restore logic" || fail "fix.sh: no auto-restore"
grep -q 'Documents/OneClaw' "$SCRIPT_DIR/fix.sh" && pass "fix.sh: creates desktop shortcuts" || fail "fix.sh: no shortcuts"

# ============================================================================
section "37. backup-restore.sh — E2E Functional Test"
# ============================================================================

# Create temp test environment
BR_TEST_DIR=$(mktemp -d)
mkdir -p "$BR_TEST_DIR/.aws" "$BR_TEST_DIR/.claude" "$BR_TEST_DIR/.openclaw/workspace" "$BR_TEST_DIR/.openclaw/scripts"
echo '{"test":true}' > "$BR_TEST_DIR/.openclaw/openclaw.json"
echo '{"env":{}}' > "$BR_TEST_DIR/.claude/settings.json"
echo '{}' > "$BR_TEST_DIR/.mcp.json"
echo '[default]' > "$BR_TEST_DIR/.aws/credentials"

# Override HOME for test
BR_BACKUP_OUT="$BR_TEST_DIR/backups"
HOME_ORIG="$HOME"
export HOME="$BR_TEST_DIR"

# Test backup
BACKUP_RESULT=$(bash "$SCRIPT_DIR/backup-restore.sh" backup "$BR_BACKUP_OUT" 2>&1)
if echo "$BACKUP_RESULT" | grep -q 'Backup created'; then
    pass "E2E: backup creates tar.gz"
else
    fail "E2E: backup failed: $BACKUP_RESULT"
fi

# Verify tar exists
BACKUP_FILE=$(find "$BR_BACKUP_OUT" -name "oneclaw-backup-*.tar.gz" 2>/dev/null | head -1)
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    pass "E2E: backup file exists"
    # Verify contents
    tar -tzf "$BACKUP_FILE" 2>/dev/null | grep -q 'openclaw.json' && pass "E2E: tar contains openclaw.json" || fail "E2E: tar missing openclaw.json"
    tar -tzf "$BACKUP_FILE" 2>/dev/null | grep -q 'settings.json' && pass "E2E: tar contains settings.json" || fail "E2E: tar missing settings.json"
else
    fail "E2E: backup file not found"
    fail "E2E: tar contents (skipped)"
    fail "E2E: tar contents (skipped)"
fi

# Test list
LIST_RESULT=$(bash "$SCRIPT_DIR/backup-restore.sh" list "$BR_BACKUP_OUT" 2>&1)
echo "$LIST_RESULT" | grep -q 'oneclaw-backup' && pass "E2E: list shows backup" || fail "E2E: list empty"

# Test restore (into a clean dir)
if [ -n "$BACKUP_FILE" ]; then
    rm -f "$BR_TEST_DIR/.openclaw/openclaw.json"
    bash "$SCRIPT_DIR/backup-restore.sh" restore "$BACKUP_FILE" >/dev/null 2>&1
    [ -f "$BR_TEST_DIR/.openclaw/openclaw.json" ] && pass "E2E: restore recovers files" || fail "E2E: restore failed"
else
    fail "E2E: restore (skipped, no backup)"
fi

# Cleanup
export HOME="$HOME_ORIG"
rm -rf "$BR_TEST_DIR"

# ============================================================================
section "38. docker-compose.yml — Structure Validation"
# ============================================================================

if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys
try:
    # PyYAML may not be installed, use basic validation
    with open('$SCRIPT_DIR/docker-compose.yml') as f:
        content = f.read()
    # Check required keys exist
    assert 'services:' in content, 'no services key'
    assert 'volumes:' in content, 'no volumes key'
    assert 'openclaw:' in content, 'no openclaw service'
    assert 'chrome:' in content, 'no chrome service'
    print('VALID')
except Exception as e:
    print(f'INVALID: {e}')
    sys.exit(1)
" 2>/dev/null && pass "docker-compose.yml: structure valid" || fail "docker-compose.yml: structure invalid"
else
    skip "python3 not available for YAML check"
fi

grep -q 'shm_size' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: chrome has shm_size (prevents crashes)" || fail "Docker: no shm_size"
grep -q 'unless-stopped' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker: restart policy set" || fail "Docker: no restart policy"

# ============================================================================
section "39. README — Completeness Check"
# ============================================================================

for readme in README.md README.zh.md; do
    [ -f "$SCRIPT_DIR/$readme" ] || continue
    grep -qi 'uninstall\|卸载' "$SCRIPT_DIR/$readme" && pass "$readme: uninstall section" || fail "$readme: no uninstall"
    grep -qi 'security\|安全' "$SCRIPT_DIR/$readme" && pass "$readme: security section" || fail "$readme: no security"
    grep -qi 'troubleshoot\|问题\|修复' "$SCRIPT_DIR/$readme" && pass "$readme: troubleshooting" || fail "$readme: no troubleshooting"
    grep -qi 'skill' "$SCRIPT_DIR/$readme" && pass "$readme: skills section" || fail "$readme: no skills"
    grep -qi 'MIT' "$SCRIPT_DIR/$readme" && pass "$readme: license" || fail "$readme: no license"
done

# ============================================================================
section "40. setup.sh — Log Rotation Script Validity"
# ============================================================================

# Extract rotate-logs.sh and validate
ROTATE_TMP=$(mktemp)
sed -n "/^cat > .*rotate-logs.sh.*<<'ROTATE_EOF'/,/^ROTATE_EOF/p" "$SCRIPT_DIR/setup.sh" | sed '1d;$d' > "$ROTATE_TMP" 2>/dev/null
if [ -s "$ROTATE_TMP" ]; then
    bash -n "$ROTATE_TMP" 2>/dev/null && pass "Embedded rotate-logs.sh: syntax OK" || fail "Embedded rotate-logs.sh: syntax error"
    grep -q 'stat' "$ROTATE_TMP" && pass "rotate-logs.sh: checks file size" || fail "rotate-logs.sh: no size check"
    grep -q 'cp.*logfile' "$ROTATE_TMP" && pass "rotate-logs.sh: copies before truncate" || fail "rotate-logs.sh: unsafe rotation"
else
    fail "rotate-logs.sh: could not extract"
fi
rm -f "$ROTATE_TMP"

# ============================================================================
section "41. Multi-Platform Messaging Support"
# ============================================================================

# Lark/Feishu
grep -q 'LARK_APP_ID' "$SCRIPT_DIR/setup.sh" && pass "Lark: App ID collection" || fail "Lark: App ID missing"
grep -q 'LARK_APP_SECRET' "$SCRIPT_DIR/setup.sh" && pass "Lark: App Secret collection" || fail "Lark: App Secret missing"
grep -q 'open.feishu.cn' "$SCRIPT_DIR/setup.sh" && pass "Lark: setup guide URL" || fail "Lark: no guide"
grep -q 'PLIST_LARK' "$SCRIPT_DIR/setup.sh" && pass "Lark: injected into LaunchAgent" || fail "Lark: not in plist"

# Telegram
grep -q 'TELEGRAM_BOT_TOKEN' "$SCRIPT_DIR/setup.sh" && pass "Telegram: token collection" || fail "Telegram: missing"
grep -q 'BotFather' "$SCRIPT_DIR/setup.sh" && pass "Telegram: setup guide" || fail "Telegram: no guide"
grep -q 'PLIST_TG' "$SCRIPT_DIR/setup.sh" && pass "Telegram: injected into LaunchAgent" || fail "Telegram: not in plist"

# Slack
grep -q 'SLACK_BOT_TOKEN' "$SCRIPT_DIR/setup.sh" && pass "Slack: token collection" || fail "Slack: missing"
grep -q 'api.slack.com' "$SCRIPT_DIR/setup.sh" && pass "Slack: setup guide URL" || fail "Slack: no guide"
grep -q 'PLIST_SLACK' "$SCRIPT_DIR/setup.sh" && pass "Slack: injected into LaunchAgent" || fail "Slack: not in plist"

# ============================================================================
section "42. Enhanced MCP Servers"
# ============================================================================

grep -q 'playwright' "$SCRIPT_DIR/setup.sh" && pass "MCP: Playwright server" || fail "MCP: Playwright missing"
grep -q 'mcp-server-github' "$SCRIPT_DIR/setup.sh" && pass "MCP: GitHub server" || fail "MCP: GitHub missing"
grep -q 'mcp-server-filesystem' "$SCRIPT_DIR/setup.sh" && pass "MCP: Filesystem server" || fail "MCP: Filesystem missing"
grep -q 'chrome-devtools-mcp' "$SCRIPT_DIR/setup.sh" && pass "MCP: Chrome DevTools (retained)" || fail "MCP: Chrome missing"
grep -q 'aws-documentation-mcp' "$SCRIPT_DIR/setup.sh" && pass "MCP: AWS Docs (retained)" || fail "MCP: AWS Docs missing"

# ============================================================================
section "43. Community Skills Installation"
# ============================================================================

grep -q 'feishu-bridge' "$SCRIPT_DIR/setup.sh" && pass "Skill: feishu-bridge" || fail "Skill: feishu-bridge missing"
grep -q 'playwright-cli' "$SCRIPT_DIR/setup.sh" && pass "Skill: playwright-cli" || fail "Skill: playwright-cli missing"
grep -q 'clawbrowser' "$SCRIPT_DIR/setup.sh" && pass "Skill: clawbrowser" || fail "Skill: clawbrowser missing"
grep -q 'clawhub' "$SCRIPT_DIR/setup.sh" && pass "Skill: clawhub CLI" || fail "Skill: clawhub missing"
grep -q 'architecture-svg' "$SCRIPT_DIR/setup.sh" && pass "Skill: architecture-svg (bundled)" || fail "Skill: architecture-svg missing"

# ============================================================================
section "44. Regression — Syntax After Platform Changes"
# ============================================================================

bash -n "$SCRIPT_DIR/setup.sh" 2>/dev/null && pass "setup.sh: syntax OK (post-platform)" || fail "setup.sh: BROKEN"
bash -n "$SCRIPT_DIR/install-linux.sh" 2>/dev/null && pass "install-linux.sh: syntax OK (post-platform)" || fail "install-linux.sh: BROKEN"

# ============================================================================
section "45. WeCom (企业微信) Support"
# ============================================================================

grep -q 'WECOM_CORP_ID' "$SCRIPT_DIR/setup.sh" && pass "WeCom: Corp ID collection" || fail "WeCom: Corp ID missing"
grep -q 'WECOM_AGENT_ID' "$SCRIPT_DIR/setup.sh" && pass "WeCom: Agent ID collection" || fail "WeCom: Agent ID missing"
grep -q 'WECOM_SECRET' "$SCRIPT_DIR/setup.sh" && pass "WeCom: Secret collection" || fail "WeCom: Secret missing"
grep -q 'WECOM_WEBHOOK_URL' "$SCRIPT_DIR/setup.sh" && pass "WeCom: Webhook URL collection" || fail "WeCom: Webhook missing"
grep -q 'work.weixin.qq.com' "$SCRIPT_DIR/setup.sh" && pass "WeCom: setup guide URL" || fail "WeCom: no guide"
grep -q 'PLIST_WECOM' "$SCRIPT_DIR/setup.sh" && pass "WeCom: injected into LaunchAgent" || fail "WeCom: not in plist"
grep -q 'openclaw/skills/wecom' "$SCRIPT_DIR/setup.sh" && pass "WeCom: skill installed" || fail "WeCom: skill missing"

# ============================================================================
section "46. Personal WeChat (Wechaty) Support"
# ============================================================================

grep -q 'INSTALL_WECHAT' "$SCRIPT_DIR/setup.sh" && pass "WeChat: install prompt" || fail "WeChat: prompt missing"
grep -q 'wechat-channel' "$SCRIPT_DIR/setup.sh" && pass "WeChat: wechat-channel skill" || fail "WeChat: skill missing"
grep -q 'Wechaty' "$SCRIPT_DIR/setup.sh" && pass "WeChat: Wechaty mentioned" || fail "WeChat: Wechaty missing"
grep -q '封号风险\|小号' "$SCRIPT_DIR/setup.sh" && pass "WeChat: risk warning" || fail "WeChat: no risk warning"

# ============================================================================
section "47. WhatsApp Support"
# ============================================================================

grep -q 'ENABLE_WHATSAPP' "$SCRIPT_DIR/setup.sh" && pass "WhatsApp: enable prompt" || fail "WhatsApp: prompt missing"
grep -q 'openclaw connect whatsapp' "$SCRIPT_DIR/setup.sh" && pass "WhatsApp: connect command" || fail "WhatsApp: connect missing"

# ============================================================================
section "48. Channel Summary Output"
# ============================================================================

grep -q '已配置的消息平台' "$SCRIPT_DIR/setup.sh" && pass "Output: channel summary section" || fail "Output: no channel summary"
grep -q 'Discord' "$SCRIPT_DIR/setup.sh" && pass "Output: Discord in summary" || fail "Output: Discord missing"
grep -q '企业微信' "$SCRIPT_DIR/setup.sh" && pass "Output: WeCom in summary" || fail "Output: WeCom missing"
grep -q 'WhatsApp' "$SCRIPT_DIR/setup.sh" && pass "Output: WhatsApp in summary" || fail "Output: WhatsApp missing"

# ============================================================================
section "49. Full Platform Coverage — All 7 Channels"
# ============================================================================

for channel in DISCORD_BOT_TOKEN LARK_APP_ID TELEGRAM_BOT_TOKEN SLACK_BOT_TOKEN WECOM_CORP_ID INSTALL_WECHAT ENABLE_WHATSAPP; do
    grep -q "$channel" "$SCRIPT_DIR/setup.sh" && pass "Channel var: $channel" || fail "Channel var: $channel missing"
done

# ============================================================================
section "50. Final Regression — All Scripts"
# ============================================================================

for script in setup.sh install-linux.sh fix.sh backup-restore.sh; do
    [ -f "$SCRIPT_DIR/$script" ] || continue
    bash -n "$SCRIPT_DIR/$script" 2>/dev/null && pass "$script: final syntax OK" || fail "$script: BROKEN"
done

if command -v shellcheck >/dev/null 2>&1; then
    ISSUES=$(shellcheck -S warning -e SC2034,SC1091,SC2086,SC2129,SC2016,SC2046,SC2015,SC2181 "$SCRIPT_DIR/setup.sh" 2>&1 | grep -c "^In " || true)
    [ "$ISSUES" -eq 0 ] && pass "setup.sh: shellcheck clean (final)" || fail "setup.sh: shellcheck $ISSUES warnings"
fi

# ============================================================================
section "51. install-linux.sh — Full MCP Parity with setup.sh"
# ============================================================================

grep -q 'playwright' "$SCRIPT_DIR/install-linux.sh" && pass "Linux MCP: Playwright" || fail "Linux MCP: Playwright missing"
grep -q 'mcp-server-github' "$SCRIPT_DIR/install-linux.sh" && pass "Linux MCP: GitHub" || fail "Linux MCP: GitHub missing"
grep -q 'mcp-server-filesystem' "$SCRIPT_DIR/install-linux.sh" && pass "Linux MCP: Filesystem" || fail "Linux MCP: Filesystem missing"
grep -q 'mcp__playwright__' "$SCRIPT_DIR/install-linux.sh" && pass "Linux perms: Playwright allowed" || fail "Linux perms: Playwright missing"
grep -q 'mcp__github__' "$SCRIPT_DIR/install-linux.sh" && pass "Linux perms: GitHub allowed" || fail "Linux perms: GitHub missing"
grep -q 'mcp__filesystem__' "$SCRIPT_DIR/install-linux.sh" && pass "Linux perms: Filesystem allowed" || fail "Linux perms: Filesystem missing"

# ============================================================================
section "52. install-linux.sh — Multi-Platform Messaging"
# ============================================================================

grep -q 'DISCORD_BOT_TOKEN' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: Discord" || fail "Linux channel: Discord missing"
grep -q 'TELEGRAM_BOT_TOKEN' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: Telegram" || fail "Linux channel: Telegram missing"
grep -q 'SLACK_BOT_TOKEN' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: Slack" || fail "Linux channel: Slack missing"
grep -q 'LARK_APP_ID' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: Lark" || fail "Linux channel: Lark missing"
grep -q 'WECOM_CORP_ID' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: WeCom" || fail "Linux channel: WeCom missing"
grep -q 'WECOM_WEBHOOK_URL' "$SCRIPT_DIR/install-linux.sh" && pass "Linux channel: WeCom Webhook" || fail "Linux channel: WeCom Webhook missing"

# ============================================================================
section "53. docker-compose.yml — Platform Env Vars"
# ============================================================================

grep -q 'DISCORD_BOT_TOKEN' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker env: Discord" || fail "Docker env: Discord missing"
grep -q 'TELEGRAM_BOT_TOKEN' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker env: Telegram" || fail "Docker env: Telegram missing"
grep -q 'SLACK_BOT_TOKEN' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker env: Slack" || fail "Docker env: Slack missing"
grep -q 'LARK_APP_ID' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker env: Lark" || fail "Docker env: Lark missing"
grep -q 'WECOM_CORP_ID' "$SCRIPT_DIR/docker-compose.yml" && pass "Docker env: WeCom" || fail "Docker env: WeCom missing"

# ============================================================================
section "54. Cross-Platform Parity Check"
# ============================================================================

# Verify setup.sh and install-linux.sh have the same MCP servers
for mcp in chrome-devtools playwright github filesystem aws-documentation; do
    MAC=$(grep -c "$mcp" "$SCRIPT_DIR/setup.sh" || true)
    LIN=$(grep -c "$mcp" "$SCRIPT_DIR/install-linux.sh" || true)
    if [ "$MAC" -gt 0 ] && [ "$LIN" -gt 0 ]; then
        pass "MCP parity: $mcp (mac=$MAC, linux=$LIN)"
    else
        fail "MCP parity: $mcp (mac=$MAC, linux=$LIN)"
    fi
done

# ============================================================================
section "55. Final Regression — All Files"
# ============================================================================

for f in setup.sh install-linux.sh fix.sh backup-restore.sh; do
    bash -n "$SCRIPT_DIR/$f" 2>/dev/null && pass "$f: syntax OK (final)" || fail "$f: BROKEN"
done
if command -v shellcheck >/dev/null 2>&1; then
    for f in setup.sh install-linux.sh fix.sh; do
        SC=$(shellcheck -S warning -e SC2034,SC1091,SC2086,SC2129,SC2016,SC2046,SC2015,SC2181 "$SCRIPT_DIR/$f" 2>&1 | grep -c "^In " || true)
        [ "$SC" -eq 0 ] && pass "$f: shellcheck clean (final)" || fail "$f: shellcheck $SC warnings"
    done
fi

# ============================================================================
section "56. MCP Parity — All 7 Servers on Both Platforms"
# ============================================================================

for mcp in chrome-devtools playwright github filesystem sequential-thinking brave-search aws-documentation; do
    MAC=$(grep -c "$mcp" "$SCRIPT_DIR/setup.sh" || true)
    LIN=$(grep -c "$mcp" "$SCRIPT_DIR/install-linux.sh" || true)
    if [ "$MAC" -gt 0 ] && [ "$LIN" -gt 0 ]; then
        pass "MCP parity: $mcp"
    else
        fail "MCP parity: $mcp (mac=$MAC, linux=$LIN)"
    fi
done

# ============================================================================
section "57. Claude Code Permissions — All MCP Allowed"
# ============================================================================

for mcp in chrome-devtools playwright github filesystem sequential-thinking brave-search aws-documentation; do
    grep -q "mcp__${mcp}__" "$SCRIPT_DIR/setup.sh" && pass "macOS allow: $mcp" || fail "macOS allow: $mcp missing"
    grep -q "mcp__${mcp}__\|mcp__${mcp}" "$SCRIPT_DIR/install-linux.sh" && pass "Linux allow: $mcp" || fail "Linux allow: $mcp missing"
done

# ============================================================================
section "58. Memory System"
# ============================================================================

grep -q 'memory/logs' "$SCRIPT_DIR/setup.sh" && pass "macOS: memory/logs dir" || fail "macOS: memory/logs missing"
grep -q 'memory/projects' "$SCRIPT_DIR/setup.sh" && pass "macOS: memory/projects dir" || fail "macOS: memory/projects missing"
grep -q 'memory/logs' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: memory/logs dir" || fail "Linux: memory/logs missing"
grep -q 'memory/projects' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: memory/projects dir" || fail "Linux: memory/projects missing"
grep -q 'MEMORY.md' "$SCRIPT_DIR/setup.sh" && pass "macOS: MEMORY.md created" || fail "macOS: MEMORY.md missing"
grep -q 'MEMORY.md' "$SCRIPT_DIR/install-linux.sh" && pass "Linux: MEMORY.md created" || fail "Linux: MEMORY.md missing"

# ============================================================================
section "59. Enhanced CLAUDE.md — Both Platforms"
# ============================================================================

grep -q 'Memory System\|Memory' "$SCRIPT_DIR/setup.sh" && pass "macOS CLAUDE.md: memory section" || fail "macOS CLAUDE.md: no memory"
grep -q 'Self-Maintenance\|auto-update' "$SCRIPT_DIR/setup.sh" && pass "macOS CLAUDE.md: self-maintenance" || fail "macOS CLAUDE.md: no maintenance"
grep -q 'Sequential Thinking' "$SCRIPT_DIR/setup.sh" && pass "macOS CLAUDE.md: sequential thinking" || fail "macOS CLAUDE.md: no seq thinking"
grep -q 'Memory' "$SCRIPT_DIR/install-linux.sh" && pass "Linux CLAUDE.md: memory section" || fail "Linux CLAUDE.md: no memory"
grep -q 'auto-update' "$SCRIPT_DIR/install-linux.sh" && pass "Linux CLAUDE.md: self-maintenance" || fail "Linux CLAUDE.md: no maintenance"

# ============================================================================
section "60. ClawHub Skills — Both Platforms"
# ============================================================================

for skill in memory-setup auto-updater feishu-bridge wecom playwright-cli clawbrowser clawhub; do
    grep -q "$skill" "$SCRIPT_DIR/setup.sh" && pass "macOS skill: $skill" || fail "macOS skill: $skill missing"
    grep -q "$skill" "$SCRIPT_DIR/install-linux.sh" && pass "Linux skill: $skill" || fail "Linux skill: $skill missing"
done

# ============================================================================
section "61. Final Regression"
# ============================================================================

for f in setup.sh install-linux.sh fix.sh backup-restore.sh; do
    bash -n "$SCRIPT_DIR/$f" 2>/dev/null && pass "$f: syntax OK" || fail "$f: BROKEN"
done
if command -v shellcheck >/dev/null 2>&1; then
    for f in setup.sh install-linux.sh; do
        SC=$(shellcheck -S warning -e SC2034,SC1091,SC2086,SC2129,SC2016,SC2046,SC2015,SC2181 "$SCRIPT_DIR/$f" 2>&1 | grep -c "^In " || true)
        [ "$SC" -eq 0 ] && pass "$f: shellcheck clean" || fail "$f: shellcheck $SC warnings"
    done
fi
# Summary
# ============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n${RED}${BOLD}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "\n${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    exit 0
fi
