#!/bin/bash
# ============================================================================
# OneClaw Linux Installer
# ============================================================================
# One-click setup for Claude Code + OpenClaw on Linux (Ubuntu/Debian/RHEL/Fedora)
# Usage: curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/install-linux.sh | bash
#
# Differences from macOS setup.sh:
#   - Uses systemd instead of LaunchAgents
#   - Installs Chromium instead of Google Chrome
#   - Detects package manager (apt/dnf/yum)
#   - No Xcode dependency
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}=== Step $1: $2 ===${NC}\n"; }

check_command() { command -v "$1" >/dev/null 2>&1; }

# Spinner for long-running commands
spin() {
    local pid=$1 msg="${2:-Working...}"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${chars:i++%${#chars}:1}" "$msg"
        sleep 0.1
    done
    printf "\r\033[K"  # clear spinner line
    wait "$pid"
    return $?
}

# Detect package manager
detect_pkg_manager() {
    if check_command apt-get; then echo "apt"
    elif check_command dnf; then echo "dnf"
    elif check_command yum; then echo "yum"
    elif check_command pacman; then echo "pacman"
    else echo "unknown"; fi
}

PKG_MGR=$(detect_pkg_manager)

pkg_install() {
    case "$PKG_MGR" in
        apt)    sudo apt-get install -y "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        yum)    sudo yum install -y "$@" ;;
        pacman) sudo pacman -S --noconfirm "$@" ;;
        *)      error "Unsupported package manager. Install manually: $*" ;;
    esac
}

# ============================================================================
echo -e "\n${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     OneClaw: Linux Setup Script                  ║"
echo "  ║   Claude Code + OpenClaw + AWS on Linux          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

[[ "$(uname)" == "Linux" ]] || error "This script only runs on Linux. For macOS use setup.sh."

ARCH=$(uname -m)
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi
info "Detected: Linux $(uname -r) ($ARCH), package manager: $PKG_MGR$(${IS_WSL} && echo ', WSL detected')"

if $IS_WSL; then
    warn "WSL 环境检测到。注意事项："
    echo -e "  - WSL1 不支持 systemd，服务需手动启动"
    echo -e "  - WSL2 需要在 /etc/wsl.conf 中启用 systemd："
    echo -e "    ${CYAN}[boot]${NC}"
    echo -e "    ${CYAN}systemd=true${NC}"
    echo -e "  - 重启 WSL 后生效: ${CYAN}wsl --shutdown${NC} 然后重新打开"
    echo ""
    # Check if systemd is actually running
    if ! pidof systemd >/dev/null 2>&1; then
        warn "systemd 未运行。服务将无法自动启动，需手动运行："
        echo -e "  ${CYAN}openclaw gateway --port 18789 &${NC}"
        echo -e "  ${CYAN}openclaw node run --host 127.0.0.1 --port 18789 &${NC}"
        echo ""
        SKIP_SYSTEMD=true
    fi
fi
SKIP_SYSTEMD="${SKIP_SYSTEMD:-false}"

# --- Language detection ---
USE_ZH=false
case "${LANG:-}${LC_ALL:-}${LANGUAGE:-}" in
    *zh_CN*|*zh_TW*|*zh_HK*|*zh.*) USE_ZH=true ;;
esac

msg_auth_prompt() {
    if $USE_ZH; then echo "请选择 AWS 认证方式："; else echo "Choose AWS authentication method:"; fi
}
msg_region_prompt() {
    if $USE_ZH; then echo "AWS Bedrock 区域"; else echo "AWS Bedrock region"; fi
}
msg_install_done() {
    if $USE_ZH; then echo "安装完成！"; else echo "Installation complete!"; fi
}

# ============================================================================
step 1 "Install prerequisites"
# ============================================================================

# Essential build tools
info "Installing build essentials..."
case "$PKG_MGR" in
    apt)    sudo apt-get update -qq && pkg_install curl git unzip build-essential ;;
    dnf|yum) pkg_install curl git unzip gcc gcc-c++ make ;;
    pacman) pkg_install curl git unzip base-devel ;;
esac

# ============================================================================
step 2 "Install Claude Code"
# ============================================================================

if check_command claude; then
    success "Claude Code already installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    info "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    success "Claude Code installed"
fi

# ============================================================================
step 3 "Configure AWS credentials"
# ============================================================================

echo -e "${BOLD}$(msg_auth_prompt)${NC}"
echo -e "  ${GREEN}1${NC}) Access Key + Secret Key"
echo -e "  ${GREEN}2${NC}) AWS SSO / IAM Identity Center"
echo -e "  ${GREEN}3${NC}) $($USE_ZH && echo '使用已有 AWS Profile' || echo 'Use existing AWS Profile')"
echo -e "  ${GREEN}4${NC}) $($USE_ZH && echo '跳过' || echo 'Skip')"
echo ""

while true; do
    echo -en "${YELLOW}请选择 [1/2/3/4]: ${NC}"
    read -r AUTH_CHOICE
    case "$AUTH_CHOICE" in
        1|2|3|4) break ;;
        *) warn "请输入 1-4" ;;
    esac
done

AWS_PROFILE_NAME="default"
AWS_BEDROCK_REGION="us-west-2"

echo ""
echo -en "${YELLOW}$(msg_region_prompt) [us-west-2]: ${NC}"
read -r AWS_BEDROCK_REGION
AWS_BEDROCK_REGION="${AWS_BEDROCK_REGION:-us-west-2}"

mkdir -p "$HOME/.aws"

case "$AUTH_CHOICE" in
    1)
        echo -en "${YELLOW}AWS Access Key ID: ${NC}"; read -r AWS_AK
        echo -en "${YELLOW}AWS Secret Access Key: ${NC}"; read -rs AWS_SK; echo ""
        cat >> "$HOME/.aws/credentials" <<EOF

[default]
aws_access_key_id = ${AWS_AK}
aws_secret_access_key = ${AWS_SK}
EOF
        cat >> "$HOME/.aws/config" <<EOF

[default]
region = ${AWS_BEDROCK_REGION}
output = json
EOF
        success "AWS credentials written"
        ;;
    2)
        echo -en "${YELLOW}SSO Start URL: ${NC}"; read -r SSO_URL
        echo -en "${YELLOW}SSO Region [us-east-1]: ${NC}"; read -r SSO_REGION; SSO_REGION="${SSO_REGION:-us-east-1}"
        echo -en "${YELLOW}Account ID: ${NC}"; read -r SSO_ACCOUNT
        echo -en "${YELLOW}Role Name: ${NC}"; read -r SSO_ROLE
        echo -en "${YELLOW}Profile name [bedrock-sso]: ${NC}"; read -r AWS_PROFILE_NAME; AWS_PROFILE_NAME="${AWS_PROFILE_NAME:-bedrock-sso}"
        cat >> "$HOME/.aws/config" <<EOF

[profile ${AWS_PROFILE_NAME}]
sso_start_url = ${SSO_URL}
sso_region = ${SSO_REGION}
sso_account_id = ${SSO_ACCOUNT}
sso_role_name = ${SSO_ROLE}
region = ${AWS_BEDROCK_REGION}
output = json
EOF
        success "SSO profile written"
        ;;
    3)
        echo -en "${YELLOW}Profile name [default]: ${NC}"; read -r AWS_PROFILE_NAME
        AWS_PROFILE_NAME="${AWS_PROFILE_NAME:-default}"
        ;;
    4) info "Skipping AWS config" ;;
esac

# --- Messaging Platforms (optional) ---
echo ""
echo -e "${BOLD}$($USE_ZH && echo '配置消息平台（全部可选，按回车跳过）' || echo 'Configure messaging platforms (all optional, press Enter to skip)')${NC}"

echo -en "${YELLOW}Discord Bot Token: ${NC}"; read -r DISCORD_BOT_TOKEN; DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
echo -en "${YELLOW}Telegram Bot Token: ${NC}"; read -r TELEGRAM_BOT_TOKEN; TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
echo -en "${YELLOW}Slack Bot Token: ${NC}"; read -r SLACK_BOT_TOKEN; SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
echo -en "${YELLOW}飞书/Lark App ID: ${NC}"; read -r LARK_APP_ID; LARK_APP_ID="${LARK_APP_ID:-}"
if [ -n "$LARK_APP_ID" ]; then
    echo -en "${YELLOW}飞书 App Secret: ${NC}"; read -rs LARK_APP_SECRET; echo ""; LARK_APP_SECRET="${LARK_APP_SECRET:-}"
else
    LARK_APP_SECRET=""
fi
echo -en "${YELLOW}企业微信 Corp ID: ${NC}"; read -r WECOM_CORP_ID; WECOM_CORP_ID="${WECOM_CORP_ID:-}"
if [ -n "$WECOM_CORP_ID" ]; then
    echo -en "${YELLOW}企业微信 Agent ID: ${NC}"; read -r WECOM_AGENT_ID; WECOM_AGENT_ID="${WECOM_AGENT_ID:-}"
    echo -en "${YELLOW}企业微信 Secret: ${NC}"; read -rs WECOM_SECRET; echo ""; WECOM_SECRET="${WECOM_SECRET:-}"
else
    WECOM_AGENT_ID=""; WECOM_SECRET=""
fi
echo -en "${YELLOW}企业微信 Webhook URL: ${NC}"; read -r WECOM_WEBHOOK_URL; WECOM_WEBHOOK_URL="${WECOM_WEBHOOK_URL:-}"

# ============================================================================
step 4 "Install fnm + Node.js + pnpm + uv + AWS CLI"
# ============================================================================

# fnm
if ! check_command fnm; then
    curl -fsSL https://fnm.vercel.app/install | bash
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env 2>/dev/null)" || true
fi
eval "$(fnm env 2>/dev/null)" || true
success "fnm ready"

# Node.js
if ! check_command node; then
    fnm install --lts && fnm use lts-latest && fnm default lts-latest
    eval "$(fnm env)"
fi
success "Node.js $(node --version)"

# pnpm
if ! check_command pnpm; then
    corepack enable 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null || npm install -g pnpm
fi
success "pnpm ready"

# uv
if ! check_command uv; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
success "uv ready"

# AWS CLI
if ! check_command aws; then
    info "Installing AWS CLI..."
    AWSCLI_TMP="/tmp/awscli-$$"
    mkdir -p "$AWSCLI_TMP"
    if [ "$ARCH" = "aarch64" ]; then
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "$AWSCLI_TMP/awscliv2.zip" &
        spin $! "Downloading AWS CLI (aarch64)..."
    else
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$AWSCLI_TMP/awscliv2.zip" &
        spin $! "Downloading AWS CLI (x86_64)..."
    fi
    unzip -q "$AWSCLI_TMP/awscliv2.zip" -d "$AWSCLI_TMP"
    sudo "$AWSCLI_TMP/aws/install" --update
    rm -rf "$AWSCLI_TMP"
fi
success "AWS CLI ready"

# SSO login if needed
if [ "$AUTH_CHOICE" = "2" ]; then
    aws sso login --profile "$AWS_PROFILE_NAME" || warn "SSO login failed, run later: aws sso login --profile $AWS_PROFILE_NAME"
fi

# Chromium (for chrome-devtools MCP)
if ! check_command chromium && ! check_command chromium-browser && ! check_command google-chrome; then
    info "Installing Chromium..."
    case "$PKG_MGR" in
        apt) pkg_install chromium-browser 2>/dev/null || pkg_install chromium ;;
        dnf|yum) pkg_install chromium ;;
        pacman) pkg_install chromium ;;
    esac
fi
CHROME_BIN=$(command -v chromium || command -v chromium-browser || command -v google-chrome || echo "/usr/bin/chromium")
success "Browser ready: $CHROME_BIN"

# ============================================================================
step 5 "Install OpenClaw"
# ============================================================================

if ! check_command openclaw; then
    curl -fsSL https://openclaw.ai/install.sh | bash
    export PATH="$HOME/Library/pnpm:$HOME/.local/bin:$PATH"
    hash -r 2>/dev/null || true
fi
success "OpenClaw ready"

# ============================================================================
step 6 "Configure OpenClaw + Claude Code"
# ============================================================================

OPENCLAW_DIR="$HOME/.openclaw"
mkdir -p "$OPENCLAW_DIR"/{logs,scripts,workspace}

PROFILE_PREFIX="us"
case "$AWS_BEDROCK_REGION" in eu-*) PROFILE_PREFIX="eu" ;; ap-*) PROFILE_PREFIX="ap" ;; esac

GATEWAY_TOKEN=$(openssl rand -hex 24)
OPENCLAW_BIN=$(command -v openclaw 2>/dev/null || echo "$HOME/.local/bin/openclaw")

# Claude Code settings
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

CLAUDE_ENV_EXTRA=""
[ "$AWS_PROFILE_NAME" != "default" ] && CLAUDE_ENV_EXTRA="$(printf '\n        "AWS_PROFILE": "%s",' "$AWS_PROFILE_NAME")"
[ "$AUTH_CHOICE" = "2" ] && CLAUDE_ENV_EXTRA="${CLAUDE_ENV_EXTRA}$(printf '\n        "CLAUDE_CODE_AWS_AUTH_REFRESH": "sso:%s",' "$AWS_PROFILE_NAME")"

cat > "$CLAUDE_DIR/settings.json" <<SETTINGS_EOF
{
    "\$schema": "https://json.schemastore.org/claude-code-settings.json",
    "env": {
        "CLAUDE_CODE_USE_BEDROCK": "1",
        "AWS_REGION": "${AWS_BEDROCK_REGION}",${CLAUDE_ENV_EXTRA}
        "ANTHROPIC_MODEL": "${PROFILE_PREFIX}.anthropic.claude-opus-4-6-v1",
        "CLAUDE_CODE_SUBAGENT_MODEL": "${PROFILE_PREFIX}.anthropic.claude-sonnet-4-6",
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000"
    },
    "permissions": {
        "allow": ["Bash", "WebFetch", "Write", "Edit",
                  "mcp__chrome-devtools__*", "mcp__playwright__*",
                  "mcp__github__*", "mcp__filesystem__*",
                  "mcp__aws-documentation__*"],
        "deny": ["Bash(rm -rf /*)", "Bash(rm -rf /)", "Bash(sudo rm *)",
                 "Bash(mkfs*)", "Bash(dd if=*)"]
    }
}
SETTINGS_EOF
success "Claude Code settings written"

# MCP config
cat > "$HOME/.mcp.json" <<MCP_EOF
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "http://localhost:9222"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-playwright@latest"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-github@latest"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "" }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-filesystem@latest", "${HOME}/Documents", "${HOME}/.openclaw/workspace"]
    },
    "aws-documentation": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": { "FASTMCP_LOG_LEVEL": "ERROR" }
    }
  }
}
MCP_EOF

# OpenClaw config (same as macOS but with Linux paths)
cat > "$OPENCLAW_DIR/openclaw.json" <<OC_EOF
{
  "browser": {
    "enabled": true,
    "headless": true,
    "profiles": { "default-chrome": { "cdpPort": 9222 } }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "amazon-bedrock": {
        "baseUrl": "https://bedrock-runtime.${AWS_BEDROCK_REGION}.amazonaws.com",
        "auth": "aws-sdk",
        "api": "bedrock-converse-stream",
        "models": [
          { "id": "${PROFILE_PREFIX}.anthropic.claude-sonnet-4-6", "name": "Sonnet 4.6", "api": "bedrock-converse-stream", "contextWindow": 200000, "maxTokens": 65536 },
          { "id": "${PROFILE_PREFIX}.anthropic.claude-haiku-4-5-20251001-v1:0", "name": "Haiku 4.5", "api": "bedrock-converse-stream", "contextWindow": 200000, "maxTokens": 8192 }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "amazon-bedrock/${PROFILE_PREFIX}.anthropic.claude-sonnet-4-6" },
      "workspace": "${OPENCLAW_DIR}/workspace",
      "cliBackends": {
        "claude-code": {
          "command": "${HOME}/.local/bin/claude",
          "args": ["--dangerously-skip-permissions", "-p", "--output-format", "stream-json"],
          "output": "jsonl", "input": "arg", "sessionMode": "always"
        }
      }
    }
  },
  "gateway": {
    "port": 18789, "mode": "local", "bind": "loopback",
    "auth": { "mode": "token", "token": "${GATEWAY_TOKEN}" }
  }
}
OC_EOF
success "OpenClaw config written"

# ============================================================================
step 7 "Set up systemd services"
# ============================================================================

if $SKIP_SYSTEMD; then
    warn "Skipping systemd setup (systemd not available)"
    echo -e "  手动启动命令："
    echo -e "  ${CYAN}${OPENCLAW_BIN} gateway --port 18789 &${NC}"
    echo -e "  ${CYAN}${OPENCLAW_BIN} node run --host 127.0.0.1 --port 18789 &${NC}"
    echo ""
else

SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

# Chrome CDP service
CHROME_DATA_DIR="$OPENCLAW_DIR/chrome-profile"
mkdir -p "$CHROME_DATA_DIR"

cat > "$SYSTEMD_DIR/openclaw-chrome.service" <<EOF
[Unit]
Description=Chrome CDP for OpenClaw
After=network.target

[Service]
ExecStart=${CHROME_BIN} --headless --remote-debugging-port=9222 --user-data-dir=${CHROME_DATA_DIR} --no-first-run --no-sandbox --disable-gpu
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Gateway service
cat > "$SYSTEMD_DIR/openclaw-gateway.service" <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target openclaw-chrome.service

[Service]
ExecStart=${OPENCLAW_BIN} gateway --port 18789
Restart=always
RestartSec=5
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.local/bin:${HOME}/.local/share/fnm/aliases/default/bin:/usr/local/bin:/usr/bin:/bin
Environment=OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
$([ "$AWS_PROFILE_NAME" != "default" ] && echo "Environment=AWS_PROFILE=${AWS_PROFILE_NAME}")
$([ -n "$DISCORD_BOT_TOKEN" ] && echo "Environment=DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}")
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "Environment=TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}")
$([ -n "$SLACK_BOT_TOKEN" ] && echo "Environment=SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}")
$([ -n "$LARK_APP_ID" ] && echo "Environment=LARK_APP_ID=${LARK_APP_ID}" && echo "Environment=LARK_APP_SECRET=${LARK_APP_SECRET}")
$([ -n "$WECOM_CORP_ID" ] && echo "Environment=WECOM_CORP_ID=${WECOM_CORP_ID}" && echo "Environment=WECOM_AGENT_ID=${WECOM_AGENT_ID}" && echo "Environment=WECOM_SECRET=${WECOM_SECRET}")
$([ -n "$WECOM_WEBHOOK_URL" ] && echo "Environment=WECOM_WEBHOOK_URL=${WECOM_WEBHOOK_URL}")

[Install]
WantedBy=default.target
EOF

# Node service
cat > "$SYSTEMD_DIR/openclaw-node.service" <<EOF
[Unit]
Description=OpenClaw Node
After=openclaw-gateway.service

[Service]
ExecStart=${OPENCLAW_BIN} node run --host 127.0.0.1 --port 18789
Restart=always
RestartSec=5
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.local/bin:${HOME}/.local/share/fnm/aliases/default/bin:/usr/local/bin:/usr/bin:/bin
$([ "$AWS_PROFILE_NAME" != "default" ] && echo "Environment=AWS_PROFILE=${AWS_PROFILE_NAME}")

[Install]
WantedBy=default.target
EOF

# Guardian timer (replaces macOS LaunchAgent StartInterval)
cat > "$SYSTEMD_DIR/openclaw-guardian.service" <<EOF
[Unit]
Description=OpenClaw Guardian Health Check

[Service]
Type=oneshot
ExecStart=/bin/bash ${OPENCLAW_DIR}/scripts/guardian-check.sh
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
EOF

cat > "$SYSTEMD_DIR/openclaw-guardian.timer" <<EOF
[Unit]
Description=OpenClaw Guardian Timer

[Timer]
OnBootSec=120
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
EOF

# Enable and start
systemctl --user daemon-reload
for svc in openclaw-chrome openclaw-gateway openclaw-node; do
    systemctl --user enable "$svc" 2>/dev/null || true
    systemctl --user restart "$svc" 2>/dev/null || true
done
systemctl --user enable openclaw-guardian.timer 2>/dev/null || true
systemctl --user start openclaw-guardian.timer 2>/dev/null || true

# Enable lingering so services run without login
loginctl enable-linger "$(whoami)" 2>/dev/null || true

success "systemd services created and started"

fi  # end SKIP_SYSTEMD

# ============================================================================
step "7.5" "Configure log rotation"
# ============================================================================

LOGROTATE_CONF="$OPENCLAW_DIR/scripts/logrotate.conf"
cat > "$LOGROTATE_CONF" <<LOGROTATE_EOF
${OPENCLAW_DIR}/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    size 10M
}
LOGROTATE_EOF

# Add daily cron job for log rotation if not using systemd timer
if ! crontab -l 2>/dev/null | grep -q "oneclaw.*logrotate"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/sbin/logrotate -s ${OPENCLAW_DIR}/logs/logrotate.state ${LOGROTATE_CONF} >/dev/null 2>&1") | crontab - 2>/dev/null || true
    success "Log rotation configured (daily, keep 7 days, max 10MB)"
else
    success "Log rotation already configured"
fi

# ============================================================================
step 8 "Persist PATH in shell rc"
# ============================================================================

for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] || continue
    grep -q 'fnm env' "$RC" 2>/dev/null || echo 'eval "$(fnm env 2>/dev/null)"' >> "$RC"
    grep -q '.local/bin' "$RC" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    [ "$AWS_PROFILE_NAME" != "default" ] && {
        grep -q "AWS_PROFILE" "$RC" 2>/dev/null || echo "export AWS_PROFILE=\"${AWS_PROFILE_NAME}\"" >> "$RC"
    }
done
success "Shell rc updated"

# ============================================================================
step 9 "Verify"
# ============================================================================

sleep 3
PASS=0; FAIL=0
check() {
    if eval "$2" >/dev/null 2>&1; then success "$1"; PASS=$((PASS+1))
    else warn "$1"; FAIL=$((FAIL+1)); fi
}
check "AWS CLI" "aws --version"
check "Claude Code" "claude --version"
check "OpenClaw" "openclaw --version"
check "Gateway" "curl -s -m 3 http://127.0.0.1:18789/ -o /dev/null"

echo ""
echo -e "${GREEN}${BOLD}$(msg_install_done)${NC} (${PASS} passed, ${FAIL} warnings)"
echo ""
echo -e "  ${BOLD}Gateway Token:${NC} ${GREEN}${GATEWAY_TOKEN}${NC}"
echo ""
echo -e "  ${BOLD}常用命令：${NC}"
echo "    claude                    — Claude Code"
echo "    openclaw chat             — OpenClaw 对话"
echo "    openclaw status           — 查看状态"
echo ""
echo -e "  ${BOLD}服务管理：${NC}"
echo "    systemctl --user status openclaw-gateway"
echo "    systemctl --user restart openclaw-gateway"
echo "    journalctl --user -u openclaw-gateway -f"
echo ""
echo -e "  ${BOLD}控制面板：${NC} http://127.0.0.1:18789"
echo ""
