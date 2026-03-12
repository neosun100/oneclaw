# OneClaw Test Documentation

## Overview

- **Test runner**: `bash tests/run_tests.sh`
- **Total test cases**: 254
- **Test categories**: 40
- **Last verified**: 2026-03-12

## How to Run

```bash
# Run all tests
bash tests/run_tests.sh

# Prerequisites (optional, for shellcheck tests)
# Ubuntu/Debian: sudo apt install shellcheck
# macOS: brew install shellcheck
```

## System Support Matrix

| Platform | Script | Service Manager | Tests |
|----------|--------|----------------|-------|
| macOS Apple Silicon | `setup.sh` | LaunchAgents | #1-9, 28-33, 40 |
| Linux (apt/dnf/yum/pacman) | `install-linux.sh` | systemd | #10-13, 22-25 |
| Linux WSL2 | `install-linux.sh` | systemd detect + fallback | #22 |
| Docker | `docker-compose.yml` | Container-managed | #15, 38 |

## Test Categories

### Unit Tests (syntax, functions, static analysis)

| # | Category | Items | What it validates |
|---|----------|-------|-------------------|
| 1 | Bash Syntax Validation | 3 | `bash -n` on setup.sh, install-linux.sh, fix.sh |
| 2 | ShellCheck Static Analysis | 3 | Zero warnings (SC2034,SC1091,SC2086 excluded) |
| 18 | Security Scanner Syntax | 2 | scan.py compiles + runs on test input |
| 28 | Embedded Scripts Syntax | 3 | repair.sh, ai-repair.sh, open-claude.command extracted and validated |
| 29 | LaunchAgent Helpers | 5 | la_load, la_unload, _launchctl_has_bootstrap, GUI_UID |
| 30 | Input Functions | 4 | ask_secret (hidden), ask_optional, /dev/tty pipe-safe |
| 40 | Log Rotation Script | 3 | rotate-logs.sh syntax, size check, safe copy-before-truncate |

### Functional Tests (feature logic)

| # | Category | Items | What it validates |
|---|----------|-------|-------------------|
| 3 | Multi-Auth Menu | 4 | static-keys, sso, profile, skip modes defined |
| 4 | SSO Configuration | 6 | sso_start_url/region/account/role, AUTH_REFRESH, login trigger |
| 5 | Profile Support | 4 | AWS_PROFILE_NAME, export, verify args, Bedrock verify |
| 6 | Region Prefix Logic | 2 | eu-* → "eu", ap-* → "ap" prefix mapping |
| 7 | No local Outside Functions | 1 | Prevents bash syntax errors |
| 8 | SSO_LOGIN_PENDING Init | 1 | Safe under `set -u` |
| 9 | Shell RC Writes | 2 | Both .zshrc and .bashrc updated |
| 10 | Linux Platform Detection | 4 | apt, dnf, yum, pacman detected |
| 11 | Linux systemd Services | 5 | gateway, node, chrome, guardian timer, linger |
| 12 | Linux Multi-Auth | 3 | Auth menu, SSO config, SSO refresh |
| 13 | Architecture Detection | 2 | aarch64 and x86_64 AWS CLI URLs |
| 14 | fix.sh SSO Detection | 2 | Detects SSO profile, suggests login command |
| 19 | Guardian Logic | 7 | Syntax, max repair=3, cooldown=300s, 3-layer check, Discord |
| 22 | WSL2 Detection | 4 | IS_WSL, /proc/version, SKIP_SYSTEMD, pidof systemd |
| 23 | Log Rotation | 5 | macOS script+size, Linux config+cron+copytruncate |
| 24 | i18n Auto-Detection | 7 | USE_ZH, 3 msg functions defined AND called |
| 25 | Progress Spinner | 2 | spin() defined, kill -0 process loop |
| 31 | Chinese Symlinks | 4 | 一键修复, AI修复, 打开Claude对话, ln -sf |
| 32 | Config JSON Validity | 9 | OC: gateway/models/agents/browser/bedrock-api; Claude: BEDROCK/model/deny/rm-block |
| 33 | CLAUDE.md Generation | 3 | File generated, workspace header, control UI reference |
| 34 | Token Fix Logic | 5 | python3 JSON, BROKEN_JSON, FIXED, OK paths, openssl rand |
| 35 | Plist Entrypoint Fix | 4 | Path detection, fix tracking, plistlib, ProgramArguments |
| 36 | Embedded Repair Scripts | 3 | skip-perms, auto-restore, desktop shortcuts |

### E2E Tests (end-to-end functional)

| # | Category | Items | What it validates |
|---|----------|-------|-------------------|
| 37 | Backup/Restore E2E | 6 | Creates temp env → backup → verify tar contents → list → restore → verify recovery |
| 38 | Docker Structure | 3 | YAML valid, shm_size, restart policy |

### Integration Tests (cross-component)

| # | Category | Items | What it validates |
|---|----------|-------|-------------------|
| 15 | docker-compose.yml | 6 | Exists, ports 18789+9222, localhost-bound, healthcheck, AWS ro mount |
| 26 | Backup/Restore | 9 | File exists, syntax, 3 functions, AWS/OC/Claude coverage, help output |
| 39 | README Completeness | 10 | Both READMEs: uninstall, security, troubleshooting, skills, license |

### Regression Tests (prevent breakage)

| # | Category | Items | What it validates |
|---|----------|-------|-------------------|
| 16 | README Consistency | 8 | EN+ZH: Linux link, Docker, SSO, systemd |
| 17 | Skills Completeness | 10 | 5 skills: SKILL.md exists + YAML frontmatter |
| 20 | No Hardcoded Secrets | 4 | No AWS keys, API keys, GitHub tokens in any script |
| 21 | Ports Bind Localhost | 2 | Gateway loopback, node 127.0.0.1 |
| 27 | Final Syntax Regression | 4 | All 4 scripts pass bash -n after all changes |

## Adding New Tests

When modifying any script, add corresponding tests:

1. Open `tests/run_tests.sh`
2. Add a new `section` block before the `# Summary` comment
3. Use `pass "description"` / `fail "description"` for assertions
4. Run `bash tests/run_tests.sh` to verify

### Test helpers

```bash
pass "test name"     # Record a passing test
fail "test name"     # Record a failing test
skip "test name"     # Record a skipped test
section "N. Title"   # Start a new test section
```

### Patterns

```bash
# Check string exists in file
grep -q 'pattern' "$SCRIPT_DIR/file.sh" && pass "desc" || fail "desc"

# Extract and validate embedded heredoc
TMP=$(mktemp)
sed -n "/^cat > .*name.*<<'TAG'/,/^TAG/p" "$SCRIPT_DIR/file.sh" | sed '1d;$d' > "$TMP"
bash -n "$TMP" && pass "syntax OK" || fail "syntax error"
rm -f "$TMP"

# E2E with temp environment
TEST_DIR=$(mktemp -d)
# ... setup, run, assert ...
rm -rf "$TEST_DIR"
```

## Latest Test Run Output

```

[1. Bash Syntax Validation]
  ✓ setup.sh — syntax OK
  ✓ install-linux.sh — syntax OK
  ✓ fix.sh — syntax OK

[2. ShellCheck Static Analysis]
  ✓ setup.sh — shellcheck clean
  ✓ install-linux.sh — shellcheck clean
  ✓ fix.sh — shellcheck clean

[3. setup.sh — Multi-Auth Menu Presence]
  ✓ Auth mode: static-keys defined
  ✓ Auth mode: sso defined
  ✓ Auth mode: profile defined
  ✓ Auth mode: skip defined

[4. setup.sh — SSO Configuration]
  ✓ SSO: sso_start_url written to config
  ✓ SSO: sso_region written to config
  ✓ SSO: sso_account_id written to config
  ✓ SSO: sso_role_name written to config
  ✓ SSO: CLAUDE_CODE_AWS_AUTH_REFRESH set
  ✓ SSO: aws sso login triggered

[5. setup.sh — Profile Support]
  ✓ Profile: AWS_PROFILE_NAME variable used
  ✓ Profile: AWS_PROFILE exported
  ✓ Profile: verification uses profile args
  ✓ Profile: Bedrock verify uses profile

[6. setup.sh — Region Prefix Logic]
  ✓ Region: eu prefix handled
  ✓ Region: ap prefix handled

[7. setup.sh — No 'local' Outside Functions]
  ✓ No 'local' keyword used outside functions

[8. setup.sh — SSO_LOGIN_PENDING Initialized]
  ✓ SSO_LOGIN_PENDING initialized before use

[9. setup.sh — Shell RC Writes Both Files]
  ✓ Shell RC: BASHRC variable defined
  ✓ Shell RC: add_to_rc function used

[10. install-linux.sh — Platform Detection]
  ✓ Linux: package manager detection
  ✓ Linux: apt support
  ✓ Linux: dnf support
  ✓ Linux: pacman support

[11. install-linux.sh — systemd Services]
  ✓ Linux: gateway systemd service
  ✓ Linux: node systemd service
  ✓ Linux: chrome systemd service
  ✓ Linux: guardian timer
  ✓ Linux: loginctl enable-linger

[12. install-linux.sh — Multi-Auth]
  ✓ Linux: auth choice menu
  ✓ Linux: SSO config support
  ✓ Linux: SSO auth refresh

[13. install-linux.sh — Architecture Detection]
  ✓ Linux: aarch64 AWS CLI
  ✓ Linux: x86_64 AWS CLI

[14. fix.sh — SSO Detection]
  ✓ Fix: SSO profile detection
  ✓ Fix: SSO login suggestion

[15. docker-compose.yml — Validation]
  ✓ docker-compose.yml exists
  ✓ Docker: gateway port mapped
  ✓ Docker: chrome CDP port mapped
  ✓ Docker: ports bound to localhost
  ✓ Docker: healthcheck defined
  ✓ Docker: AWS creds mounted read-only

[16. README Consistency]
  ✓ README.md: Linux install link
  ✓ README.md: Docker instructions
  ✓ README.md: SSO documentation
  ✓ README.md: Linux systemd docs
  ✓ README.zh.md: Linux install link
  ✓ README.zh.md: Docker instructions
  ✓ README.zh.md: SSO documentation
  ✓ README.zh.md: Linux systemd docs

[17. Skills — SKILL.md Presence]
  ✓ Skill claude-code: SKILL.md exists
  ✓ Skill claude-code: has YAML frontmatter
  ✓ Skill aws-infra: SKILL.md exists
  ✓ Skill aws-infra: has YAML frontmatter
  ✓ Skill chrome-devtools: SKILL.md exists
  ✓ Skill chrome-devtools: has YAML frontmatter
  ✓ Skill skill-vetting: SKILL.md exists
  ✓ Skill skill-vetting: has YAML frontmatter
  ✓ Skill architecture-svg: SKILL.md exists
  ✓ Skill architecture-svg: has YAML frontmatter

[18. Security Scanner — Syntax]
  ✓ scan.py — Python syntax OK
  ✓ scan.py — runs successfully on test input

[19. Guardian Script — Logic Validation]
  ✓ Guardian script: syntax OK
  ✓ Guardian: max repair limit
  ✓ Guardian: cooldown period
  ✓ Guardian: process check layer
  ✓ Guardian: HTTP check layer
  ✓ Guardian: status check layer
  ✓ Guardian: Discord notification

[20. Regression — No Hardcoded Secrets]
  ✓ setup.sh: no hardcoded secrets
  ✓ install-linux.sh: no hardcoded secrets
  ✓ fix.sh: no hardcoded secrets
  ✓ docker-compose.yml: no hardcoded secrets

[21. Regression — All Ports Bind Localhost]
  ✓ setup.sh: gateway binds loopback
  ✓ install-linux.sh: node binds 127.0.0.1

[22. TODO 1 — WSL2 Detection]
  ✓ WSL: IS_WSL variable
  ✓ WSL: proc check
  ✓ WSL: SKIP_SYSTEMD guard
  ✓ WSL: systemd runtime check

[23. TODO 2 — Log Rotation]
  ✓ LogRotate macOS: script
  ✓ LogRotate macOS: size limit
  ✓ LogRotate Linux: config
  ✓ LogRotate Linux: cron
  ✓ LogRotate Linux: copytruncate

[24. TODO 3 — i18n Auto-Detection]
  ✓ i18n: USE_ZH var
  ✓ i18n: auth prompt fn
  ✓ i18n: region prompt fn
  ✓ i18n: done msg fn
  ✓ i18n: auth prompt CALLED
  ✓ i18n: region prompt CALLED
  ✓ i18n: done msg CALLED

[25. TODO 4 — Progress Spinner]
  ✓ Spinner: function defined
  ✓ Spinner: process loop

[26. TODO 5 — Backup/Restore]
  ✓ backup-restore.sh exists
  ✓ backup-restore.sh syntax OK
  ✓ Backup: backup fn
  ✓ Backup: restore fn
  ✓ Backup: list fn
  ✓ Backup: AWS creds
  ✓ Backup: OC config
  ✓ Backup: Claude cfg
  ✓ Backup: help works

[27. Regression — All Scripts Syntax (final)]
  ✓ setup.sh: final syntax OK
  ✓ install-linux.sh: final syntax OK
  ✓ fix.sh: final syntax OK
  ✓ backup-restore.sh: final syntax OK

[28. setup.sh — Embedded Scripts Syntax]
  ✓ Embedded repair.sh: syntax OK
  ✓ Embedded ai-repair.sh: syntax OK
  ✓ Embedded open-claude.command: syntax OK

[29. setup.sh — LaunchAgent Helpers]
  ✓ la_load function defined
  ✓ la_unload function defined
  ✓ _launchctl_has_bootstrap defined
  ✓ macOS version detection
  ✓ GUI UID used in launchctl

[30. setup.sh — Input Functions]
  ✓ ask_secret function defined
  ✓ ask_optional function defined
  ✓ ask_secret hides input (-s flag)
  ✓ Input reads from /dev/tty (pipe-safe)

[31. setup.sh — Chinese Symlinks]
  ✓ Chinese symlink: 一键修复
  ✓ Chinese symlink: AI修复
  ✓ Chinese symlink: 打开Claude对话
  ✓ Symlinks use ln -sf (force)

[32. setup.sh — Generated Config JSON Validity]
  ✓ OC config: gateway section
  ✓ OC config: models section
  ✓ OC config: agents section
  ✓ OC config: browser section
  ✓ OC config: bedrock API type
  ✓ Claude cfg: BEDROCK flag
  ✓ Claude cfg: model set
  ✓ Claude cfg: deny list (safety)
  ✓ Claude cfg: blocks rm -rf /*

[33. setup.sh — CLAUDE.md Generation]
  ✓ CLAUDE.md generated
  ✓ CLAUDE.md has workspace header
  ✓ CLAUDE.md references control UI

[34. fix.sh — Token Fix Logic]
  ✓ fix.sh: uses python3 for JSON
  ✓ fix.sh: handles broken JSON
  ✓ fix.sh: FIXED status path
  ✓ fix.sh: OK status path
  ✓ fix.sh: generates new token

[35. fix.sh — Plist Entrypoint Fix]
  ✓ fix.sh: detects actual binary path
  ✓ fix.sh: tracks fixed plists
  ✓ fix.sh: uses plistlib for safe edit
  ✓ fix.sh: fixes ProgramArguments[0]

[36. fix.sh — Embedded Repair Scripts]
  ✓ fix.sh: AI repair uses skip-perms
  ✓ fix.sh: auto-restore logic
  ✓ fix.sh: creates desktop shortcuts

[37. backup-restore.sh — E2E Functional Test]
  ✓ E2E: backup creates tar.gz
  ✓ E2E: backup file exists
  ✓ E2E: tar contains openclaw.json
  ✓ E2E: tar contains settings.json
  ✓ E2E: list shows backup
  ✓ E2E: restore recovers files

[38. docker-compose.yml — Structure Validation]
VALID
  ✓ docker-compose.yml: structure valid
  ✓ Docker: chrome has shm_size (prevents crashes)
  ✓ Docker: restart policy set

[39. README — Completeness Check]
  ✓ README.md: uninstall section
  ✓ README.md: security section
  ✓ README.md: troubleshooting
  ✓ README.md: skills section
  ✓ README.md: license
  ✓ README.zh.md: uninstall section
  ✓ README.zh.md: security section
  ✓ README.zh.md: troubleshooting
  ✓ README.zh.md: skills section
  ✓ README.zh.md: license

[40. setup.sh — Log Rotation Script Validity]
  ✓ Embedded rotate-logs.sh: syntax OK
  ✓ rotate-logs.sh: checks file size
  ✓ rotate-logs.sh: copies before truncate

[41. Multi-Platform Messaging Support]
  ✓ Lark: App ID collection
  ✓ Lark: App Secret collection
  ✓ Lark: setup guide URL
  ✓ Lark: injected into LaunchAgent
  ✓ Telegram: token collection
  ✓ Telegram: setup guide
  ✓ Telegram: injected into LaunchAgent
  ✓ Slack: token collection
  ✓ Slack: setup guide URL
  ✓ Slack: injected into LaunchAgent

[42. Enhanced MCP Servers]
  ✓ MCP: Playwright server
  ✓ MCP: GitHub server
  ✓ MCP: Filesystem server
  ✓ MCP: Chrome DevTools (retained)
  ✓ MCP: AWS Docs (retained)

[43. Community Skills Installation]
  ✓ Skill: feishu-bridge
  ✓ Skill: playwright-cli
  ✓ Skill: clawbrowser
  ✓ Skill: clawhub CLI
  ✓ Skill: architecture-svg (bundled)

[44. Regression — Syntax After Platform Changes]
  ✓ setup.sh: syntax OK (post-platform)
  ✓ install-linux.sh: syntax OK (post-platform)

[45. WeCom (企业微信) Support]
  ✓ WeCom: Corp ID collection
  ✓ WeCom: Agent ID collection
  ✓ WeCom: Secret collection
  ✓ WeCom: Webhook URL collection
  ✓ WeCom: setup guide URL
  ✓ WeCom: injected into LaunchAgent
  ✓ WeCom: skill installed

[46. Personal WeChat (Wechaty) Support]
  ✓ WeChat: install prompt
  ✓ WeChat: wechat-channel skill
  ✓ WeChat: Wechaty mentioned
  ✓ WeChat: risk warning

[47. WhatsApp Support]
  ✓ WhatsApp: enable prompt
  ✓ WhatsApp: connect command

[48. Channel Summary Output]
  ✓ Output: channel summary section
  ✓ Output: Discord in summary
  ✓ Output: WeCom in summary
  ✓ Output: WhatsApp in summary

[49. Full Platform Coverage — All 7 Channels]
  ✓ Channel var: DISCORD_BOT_TOKEN
  ✓ Channel var: LARK_APP_ID
  ✓ Channel var: TELEGRAM_BOT_TOKEN
  ✓ Channel var: SLACK_BOT_TOKEN
  ✓ Channel var: WECOM_CORP_ID
  ✓ Channel var: INSTALL_WECHAT
  ✓ Channel var: ENABLE_WHATSAPP

[50. Final Regression — All Scripts]
  ✓ setup.sh: final syntax OK
  ✓ install-linux.sh: final syntax OK
  ✓ fix.sh: final syntax OK
  ✓ backup-restore.sh: final syntax OK
  ✓ setup.sh: shellcheck clean (final)

[51. install-linux.sh — Full MCP Parity with setup.sh]
  ✓ Linux MCP: Playwright
  ✓ Linux MCP: GitHub
  ✓ Linux MCP: Filesystem
  ✓ Linux perms: Playwright allowed
  ✓ Linux perms: GitHub allowed
  ✓ Linux perms: Filesystem allowed

[52. install-linux.sh — Multi-Platform Messaging]
  ✓ Linux channel: Discord
  ✓ Linux channel: Telegram
  ✓ Linux channel: Slack
  ✓ Linux channel: Lark
  ✓ Linux channel: WeCom
  ✓ Linux channel: WeCom Webhook

[53. docker-compose.yml — Platform Env Vars]
  ✓ Docker env: Discord
  ✓ Docker env: Telegram
  ✓ Docker env: Slack
  ✓ Docker env: Lark
  ✓ Docker env: WeCom

[54. Cross-Platform Parity Check]
  ✓ MCP parity: chrome-devtools (mac=6, linux=4)
  ✓ MCP parity: playwright (mac=4, linux=3)
  ✓ MCP parity: github (mac=8, linux=4)
  ✓ MCP parity: filesystem (mac=3, linux=3)
  ✓ MCP parity: aws-documentation (mac=3, linux=3)

[55. Final Regression — All Files]
  ✓ setup.sh: syntax OK (final)
  ✓ install-linux.sh: syntax OK (final)
  ✓ fix.sh: syntax OK (final)
  ✓ backup-restore.sh: syntax OK (final)
  ✓ setup.sh: shellcheck clean (final)
  ✓ install-linux.sh: shellcheck clean (final)
  ✓ fix.sh: shellcheck clean (final)

═══════════════════════════════════════
  Passed: 254  Failed: 0  Skipped: 0
═══════════════════════════════════════

ALL TESTS PASSED
```
