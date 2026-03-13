#!/bin/bash
# ============================================================================
# OnClick-Claw: One-Click Setup for Claude Code + OpenClaw on Mac (Apple Silicon)
# ============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/setup.sh | bash
#   or:  bash setup.sh
#
# What it does:
#   1. Install Claude Code (no dependencies — your AI assistant for troubleshooting)
#   2. Collect AWS credentials + configure Claude Code for Bedrock
#   3. Install fnm (Fast Node Manager) + Node.js
#   4. Install pnpm, uv/uvx, AWS CLI
#   5. Install OpenClaw
#   6. Configure OpenClaw (Bedrock, browser, agents)
#   7. Set up Guardian watchdog + LaunchAgents (auto-start on boot)
#   8. Generate a CLAUDE.md for OpenClaw initialization
#
# Requirements: macOS with Apple Silicon (M1/M2/M3/M4), internet connection
# ============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}=== Step $1: $2 ===${NC}\n"; }

# --- launchctl modern API helpers (bootstrap/bootout for macOS 13+, fallback to load/unload) ---
_launchctl_has_bootstrap() {
    # macOS 13+ (Ventura) supports bootstrap/bootout
    local major
    major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    [ "${major:-0}" -ge 13 ]
}

GUI_UID=$(id -u)

la_load() {
    local plist="$1"
    local label
    label=$(basename "$plist" .plist)
    if _launchctl_has_bootstrap; then
        launchctl bootstrap "gui/${GUI_UID}" "$plist" 2>/dev/null || \
            launchctl kickstart -k "gui/${GUI_UID}/${label}" 2>/dev/null || true
    else
        launchctl load "$plist" 2>/dev/null || true
    fi
}

la_unload() {
    local plist="$1"
    local label
    label=$(basename "$plist" .plist)
    if _launchctl_has_bootstrap; then
        launchctl bootout "gui/${GUI_UID}/${label}" 2>/dev/null || true
    else
        launchctl unload "$plist" 2>/dev/null || true
    fi
}

ask_secret() {
    local prompt="$1" var_name="$2" hide="${3:-false}"
    local value=""
    while [ -z "$value" ]; do
        echo -en "${YELLOW}$prompt: ${NC}"
        if [ "$hide" = "true" ]; then
            read -rs value </dev/tty
            echo ""
        else
            read -r value </dev/tty
        fi
        [ -z "$value" ] && warn "必填项，请输入内容。"
    done
    printf -v "$var_name" '%s' "$value"
}

ask_optional() {
    local prompt="$1" var_name="$2" default="$3"
    echo -en "${YELLOW}$prompt [${default}]: ${NC}"
    read -r value </dev/tty
    value="${value:-$default}"
    printf -v "$var_name" '%s' "$value"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# Pre-flight checks
# ============================================================================
echo -e "\n${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║       All in One Claw: One-Click Setup Script       ║"
echo "  ║   Claude Code + OpenClaw + AWS — All in One    ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check macOS
[[ "$(uname)" == "Darwin" ]] || error "This script only runs on macOS."
info "Detected: macOS $(sw_vers -productVersion) ($(uname -m))"

echo ""
echo -e "${YELLOW}${BOLD}提示：${NC}安装过程需要管理员权限（sudo），请先输入你的 Mac 登录密码。"
echo -e "      密码输入时屏幕不会显示任何字符，输完按回车就行。"
echo ""

# Pre-flight sudo check — acquire sudo before anything else
if ! sudo -n true 2>/dev/null; then
    sudo -v || error "无法获取管理员权限。请确认你的账户是管理员，并输入正确的密码。"
fi
# Keep sudo alive throughout the script
(while true; do sudo -n true; sleep 50; done) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT
success "管理员权限已获取"

# ============================================================================
# Step 0.5: Xcode Command Line Tools (required for compilation tools)
# ============================================================================
if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools (may take a few minutes)..."
    xcode-select --install 2>/dev/null || true
    # Wait for installation to complete
    echo -e "${YELLOW}请在弹出的对话框中点击「安装」，等待安装完成后按回车继续...${NC}"
    read -r </dev/tty
    if ! xcode-select -p >/dev/null 2>&1; then
        echo ""
        echo -e "${RED}${BOLD}Xcode Command Line Tools 安装失败。${NC}"
        echo -e "${YELLOW}请手动执行以下命令，安装完成后重新运行本脚本：${NC}"
        echo ""
        echo -e "  ${CYAN}xcode-select --install${NC}"
        echo ""
        echo -e "  如果弹窗没出现，可以从 Apple 开发者网站下载："
        echo -e "  ${CYAN}https://developer.apple.com/download/more/${NC}"
        echo -e "  搜索 \"Command Line Tools\"，下载对应 macOS 版本的安装包。"
        echo ""
        exit 1
    fi
    success "Xcode Command Line Tools installed"
else
    success "Xcode Command Line Tools already installed"
fi

# ============================================================================
# Step 1: Install Claude Code (NO dependencies — install first as safety net)
# ============================================================================
step 1 "Install Claude Code"

echo -e "${BOLD}Claude Code 是 AI 编程助手，无额外依赖，优先安装。${NC}"
echo -e "后续步骤如果遇到问题，你可以随时打开新终端输入 ${GREEN}claude${NC} 让它帮你修复。\n"

if check_command claude; then
    success "Claude Code already installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    info "Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        export PATH="$HOME/.local/bin:$PATH"
        success "Claude Code installed"
    else
        echo -e "${RED}Claude Code 安装失败。请手动运行: ${CYAN}curl -fsSL https://claude.ai/install.sh | bash${NC}"
        exit 1
    fi
fi

# ============================================================================
# Step 2: Collect AWS credentials + Configure Claude Code for Bedrock
# ============================================================================
step 2 "配置 AWS 凭证 + Claude Code"

echo -e "${BOLD}接下来需要输入一些信息来配置环境。${NC}"
echo -e "所有信息只保存在你的电脑上，不会上传到任何地方。\n"

# --- AWS Authentication Method Selection ---
echo -e "${CYAN}--- AWS 认证方式（用于访问 Bedrock Claude 模型） ---${NC}"
echo ""
echo -e "  ${BOLD}请选择 AWS 认证方式：${NC}"
echo ""
echo -e "  ${GREEN}1${NC}) ${BOLD}Access Key + Secret Key${NC}（最简单，适合个人用户）"
echo -e "     → 输入一组 IAM 用户的 AK/SK，保存到 ~/.aws/credentials"
echo ""
echo -e "  ${GREEN}2${NC}) ${BOLD}AWS SSO / IAM Identity Center${NC}（企业推荐）"
echo -e "     → 通过浏览器登录，自动获取临时凭证，更安全"
echo ""
echo -e "  ${GREEN}3${NC}) ${BOLD}使用已有的 AWS Profile${NC}（已配置过 aws configure 的用户）"
echo -e "     → 直接复用 ~/.aws/credentials 或 ~/.aws/config 中的 profile"
echo ""
echo -e "  ${GREEN}4${NC}) ${BOLD}跳过${NC}（已有 ~/.aws/credentials 且确认可用）"
echo ""

# Detect existing credentials
AWS_AUTH_MODE=""
EXISTING_PROFILES=""
if [ -f "$HOME/.aws/credentials" ] || [ -f "$HOME/.aws/config" ]; then
    EXISTING_PROFILES=$(grep '^\[' "$HOME/.aws/credentials" "$HOME/.aws/config" 2>/dev/null | sed 's/.*\[//;s/\]//' | sed 's/^profile //' | sort -u | tr '\n' ', ' | sed 's/,$//')
    if [ -n "$EXISTING_PROFILES" ]; then
        echo -e "  ${YELLOW}检测到已有 AWS 配置，可用 profile: ${GREEN}${EXISTING_PROFILES}${NC}"
        echo ""
    fi
fi

while true; do
    echo -en "${YELLOW}请选择 [1/2/3/4]: ${NC}"
    read -r AUTH_CHOICE </dev/tty
    case "$AUTH_CHOICE" in
        1) AWS_AUTH_MODE="static-keys"; break ;;
        2) AWS_AUTH_MODE="sso"; break ;;
        3) AWS_AUTH_MODE="profile"; break ;;
        4) AWS_AUTH_MODE="skip"; break ;;
        *) warn "请输入 1、2、3 或 4" ;;
    esac
done

# --- Collect credentials based on auth mode ---
AWS_AK=""
AWS_SK=""
AWS_PROFILE_NAME="default"
AWS_SSO_START_URL=""
AWS_SSO_REGION=""
AWS_SSO_ACCOUNT_ID=""
AWS_SSO_ROLE_NAME=""

case "$AWS_AUTH_MODE" in
    static-keys)
        echo ""
        echo -e "  ${BOLD}没有 AWS 账号？${NC}找帮你装机的人要一组 Access Key 和 Secret Key。"
        echo -e "  ${BOLD}已有账号但没有密钥？${NC}登录 AWS Console → IAM → Users → 你的用户 → Security credentials → Create access key"
        echo ""
        echo -e "  ${BOLD}${YELLOW}IAM 用户需要以下权限（缺一不可）：${NC}"
        echo -e "  ${GREEN}bedrock:InvokeModel${NC}              — 调用模型"
        echo -e "  ${GREEN}bedrock:InvokeModelWithResponseStream${NC} — 流式调用"
        echo -e "  ${GREEN}bedrock:ListFoundationModels${NC}     — 列出可用模型"
        echo -e "  ${GREEN}bedrock:GetFoundationModel${NC}       — 查询模型详情"
        echo ""
        echo -e "  ${BOLD}最简方式：${NC}附加 AWS 托管策略 ${GREEN}AmazonBedrockFullAccess${NC}"
        echo ""
        ask_secret "请输入 AWS Access Key ID" AWS_AK
        ask_secret "请输入 AWS Secret Access Key（输入时不会显示）" AWS_SK true
        ;;
    sso)
        echo ""
        echo -e "  ${BOLD}AWS SSO 配置${NC}（需要管理员提供以下信息）："
        echo ""
        ask_secret "SSO Start URL（如 https://my-org.awsapps.com/start）" AWS_SSO_START_URL
        ask_optional "SSO Region（SSO 服务所在区域）" AWS_SSO_REGION "us-east-1"
        ask_secret "AWS Account ID（12 位数字）" AWS_SSO_ACCOUNT_ID
        ask_secret "SSO Role Name（如 AdministratorAccess、BedrockUser）" AWS_SSO_ROLE_NAME
        ask_optional "Profile 名称" AWS_PROFILE_NAME "bedrock-sso"
        ;;
    profile)
        echo ""
        if [ -n "$EXISTING_PROFILES" ]; then
            echo -e "  已有 profile: ${GREEN}${EXISTING_PROFILES}${NC}"
        fi
        ask_optional "要使用的 AWS Profile 名称" AWS_PROFILE_NAME "default"
        ;;
    skip)
        info "跳过 AWS 凭证配置，使用已有配置"
        ;;
esac

echo ""
echo -e "${CYAN}--- AWS 区域配置 ---${NC}"
echo -e "  默认使用 ${GREEN}us-west-2${NC}（美国西部-俄勒冈），直接按回车即可"
echo -e "  其他常用区域：us-east-1（美东）、eu-west-1（欧洲）、ap-northeast-1（东京）"
ask_optional "AWS Bedrock 区域" AWS_BEDROCK_REGION "us-west-2"

echo ""
echo -e "  ${YELLOW}请确认已在 Bedrock 控制台开启模型访问：${NC}"
echo -e "  AWS Console → Bedrock → Model access → 勾选 Anthropic Claude 全系列 → Save"
echo ""

# Claude Code uses the same region — derive inference profile prefix
CC_BEDROCK_REGION="$AWS_BEDROCK_REGION"

# Discord (optional)
echo -e "\n${CYAN}--- Discord 机器人（可选，按回车跳过） ---${NC}"
echo -e "  OpenClaw 可以连接 Discord，让你在 Discord 里和 AI 对话、接收告警通知。"
echo -e "  如果暂时不需要，两项都直接按回车跳过，以后可以再配。\n"
echo -e "  ${BOLD}如何获取 Discord Bot Token：${NC}"
echo -e "  1. 打开 ${CYAN}https://discord.com/developers/applications${NC}"
echo -e "  2. 点右上角 ${GREEN}New Application${NC} → 输入名字（如 OpenClaw）→ Create"
echo -e "  3. 左侧点 ${GREEN}机器人(Bot)${NC} → 点 ${GREEN}重置令牌(Reset Token)${NC} → 复制 Token"
echo -e "  4. 在同一页面往下找到 ${GREEN}特权网关意图(Privileged Gateway Intents)${NC}"
echo -e "     打开 ${GREEN}消息内容意图(Message Content Intent)${NC} 开关 → 点 ${GREEN}保存(Save)${NC}"
echo -e ""
echo -e "  ${BOLD}如何邀请 Bot 到你的 Discord 服务器：${NC}"
echo -e "  5. 左侧点 ${GREEN}OAuth2${NC} → 往下找到 ${GREEN}OAuth2 URL 生成器${NC}"
echo -e "     范围(Scopes)勾选: ${GREEN}bot${NC}"
echo -e "     勾选后下方出现 ${GREEN}机器人权限(Bot Permissions)${NC}，勾选:"
echo -e "     ${GREEN}Send Messages${NC} / ${GREEN}Read Message History${NC} / ${GREEN}View Channels${NC}"
echo -e "  6. 页面最下方会生成一个 URL → 点 ${GREEN}Copy${NC} → 浏览器打开"
echo -e "     选择你的服务器 → 点 ${GREEN}授权(Authorize)${NC}\n"
echo -en "${YELLOW}Discord Bot Token（没有就直接回车）: ${NC}"
read -r DISCORD_BOT_TOKEN </dev/tty
DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"

echo -e "\n  ${BOLD}如何获取 Discord Webhook URL：${NC}"
echo -e "  1. 打开 Discord → 进入你想收通知的频道"
echo -e "  2. 点频道名旁的 ⚙️ 设置 → 左侧 ${GREEN}Integrations${NC} → ${GREEN}Webhooks${NC}"
echo -e "  3. 点 ${GREEN}New Webhook${NC} → 取名（如 OpenClaw Alert）→ ${GREEN}Copy Webhook URL${NC}\n"
echo -en "${YELLOW}Discord Webhook URL（用于异常告警，没有就直接回车）: ${NC}"
read -r DISCORD_WEBHOOK_URL </dev/tty
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# Lark/Feishu (optional)
echo -e "\n${CYAN}--- 飞书/Lark 机器人（可选，按回车跳过） ---${NC}"
echo -e "  OpenClaw 可以连接飞书/Lark，让你在飞书里和 AI 对话。"
echo -e "  需要在飞书开放平台创建自建应用并添加机器人能力。\n"
echo -e "  ${BOLD}如何获取：${NC}"
echo -e "  1. 打开 ${CYAN}https://open.feishu.cn/app${NC} → 创建自建应用"
echo -e "  2. 添加「机器人」能力 → 获取 App ID 和 App Secret"
echo -e "  3. 权限管理 → 开通 ${GREEN}im:message${NC} 和 ${GREEN}im:message.create${NC}"
echo -e "  4. 事件订阅 → 添加 ${GREEN}im.message.receive_v1${NC}\n"
echo -en "${YELLOW}飞书 App ID（没有就直接回车）: ${NC}"
read -r LARK_APP_ID </dev/tty
LARK_APP_ID="${LARK_APP_ID:-}"
if [ -n "$LARK_APP_ID" ]; then
    echo -en "${YELLOW}飞书 App Secret: ${NC}"
    read -rs LARK_APP_SECRET </dev/tty; echo ""
    LARK_APP_SECRET="${LARK_APP_SECRET:-}"
else
    LARK_APP_SECRET=""
fi

# Telegram (optional)
echo -e "\n${CYAN}--- Telegram 机器人（可选，按回车跳过） ---${NC}"
echo -e "  ${BOLD}如何获取：${NC}在 Telegram 中搜索 ${GREEN}@BotFather${NC} → /newbot → 复制 Token\n"
echo -en "${YELLOW}Telegram Bot Token（没有就直接回车）: ${NC}"
read -r TELEGRAM_BOT_TOKEN </dev/tty
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

# Slack (optional)
echo -e "\n${CYAN}--- Slack 机器人（可选，按回车跳过） ---${NC}"
echo -e "  ${BOLD}如何获取：${NC}"
echo -e "  1. 打开 ${CYAN}https://api.slack.com/apps${NC} → Create New App"
echo -e "  2. OAuth & Permissions → Bot Token Scopes → 添加 ${GREEN}chat:write${NC}, ${GREEN}channels:history${NC}"
echo -e "  3. Install to Workspace → 复制 Bot User OAuth Token\n"
echo -en "${YELLOW}Slack Bot Token（没有就直接回车）: ${NC}"
read -r SLACK_BOT_TOKEN </dev/tty
SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"

# WeCom / 企业微信 (optional)
echo -e "\n${CYAN}--- 企业微信 WeCom 机器人（可选，按回车跳过） ---${NC}"
echo -e "  ${BOLD}如何获取：${NC}"
echo -e "  1. 登录 ${CYAN}https://work.weixin.qq.com${NC} → 应用管理 → 创建应用"
echo -e "  2. 获取 ${GREEN}Corp ID${NC}（企业信息页）、${GREEN}Agent ID${NC} 和 ${GREEN}Secret${NC}（应用详情页）"
echo -e "  3. 或使用群机器人 Webhook: 群聊 → 添加群机器人 → 复制 Webhook URL\n"
echo -en "${YELLOW}企业微信 Corp ID（没有就直接回车）: ${NC}"
read -r WECOM_CORP_ID </dev/tty
WECOM_CORP_ID="${WECOM_CORP_ID:-}"
if [ -n "$WECOM_CORP_ID" ]; then
    echo -en "${YELLOW}企业微信 Agent ID: ${NC}"
    read -r WECOM_AGENT_ID </dev/tty
    WECOM_AGENT_ID="${WECOM_AGENT_ID:-}"
    echo -en "${YELLOW}企业微信 Secret: ${NC}"
    read -rs WECOM_SECRET </dev/tty; echo ""
    WECOM_SECRET="${WECOM_SECRET:-}"
else
    WECOM_AGENT_ID=""
    WECOM_SECRET=""
fi
echo -en "${YELLOW}企业微信 Webhook URL（群机器人，没有就直接回车）: ${NC}"
read -r WECOM_WEBHOOK_URL </dev/tty
WECOM_WEBHOOK_URL="${WECOM_WEBHOOK_URL:-}"

# WeChat / 个人微信 (optional, via Wechaty)
echo -e "\n${CYAN}--- 个人微信（可选，实验性，按回车跳过） ---${NC}"
echo -e "  通过 Wechaty 桥接个人微信，安装后需扫码登录。"
echo -e "  ${YELLOW}注意：个人微信接口为非官方，有封号风险，建议使用小号。${NC}"
echo -e "  安装后运行 ${CYAN}openclaw connect wechat${NC} 扫码登录。\n"
echo -en "${YELLOW}是否安装个人微信桥接？[y/N]: ${NC}"
read -r INSTALL_WECHAT </dev/tty
INSTALL_WECHAT="${INSTALL_WECHAT:-N}"

# WhatsApp (optional, native via openclaw onboard)
echo -e "\n${CYAN}--- WhatsApp（可选，按回车跳过） ---${NC}"
echo -e "  OpenClaw 原生支持 WhatsApp，安装后通过 Web 控制台扫码连接。"
echo -e "  或运行 ${CYAN}openclaw connect whatsapp${NC} 扫码。\n"
echo -en "${YELLOW}是否启用 WhatsApp 支持？[y/N]: ${NC}"
read -r ENABLE_WHATSAPP </dev/tty
ENABLE_WHATSAPP="${ENABLE_WHATSAPP:-N}"

# OpenClaw gateway token — auto-generate, user doesn't need to know
GATEWAY_TOKEN=$(openssl rand -hex 24)
SSO_LOGIN_PENDING=false
info "已自动生成 Gateway 安全令牌"

# --- Write AWS credentials based on auth mode ---
info "Writing AWS credentials..."
mkdir -p "$HOME/.aws"

case "$AWS_AUTH_MODE" in
    static-keys)
        if command -v aws >/dev/null 2>&1; then
            aws configure set aws_access_key_id "$AWS_AK" --profile "$AWS_PROFILE_NAME"
            aws configure set aws_secret_access_key "$AWS_SK" --profile "$AWS_PROFILE_NAME"
            aws configure set region "$AWS_BEDROCK_REGION" --profile "$AWS_PROFILE_NAME"
            aws configure set output json --profile "$AWS_PROFILE_NAME"
            success "AWS credentials set via 'aws configure set' (profile: ${AWS_PROFILE_NAME})"
        else
            # aws cli not yet installed — write files directly
            if [ ! -f "$HOME/.aws/credentials" ] || ! grep -q "\[${AWS_PROFILE_NAME}\]" "$HOME/.aws/credentials" 2>/dev/null; then
                cat >> "$HOME/.aws/credentials" <<EOF

[${AWS_PROFILE_NAME}]
aws_access_key_id = ${AWS_AK}
aws_secret_access_key = ${AWS_SK}
EOF
                success "AWS credentials written to ~/.aws/credentials (profile: ${AWS_PROFILE_NAME})"
            else
                warn "$HOME/.aws/credentials [${AWS_PROFILE_NAME}] already exists, not overwriting"
            fi

            if [ ! -f "$HOME/.aws/config" ] || ! grep -q "\[${AWS_PROFILE_NAME}\]" "$HOME/.aws/config" 2>/dev/null; then
                CONFIG_SECTION="[${AWS_PROFILE_NAME}]"
                [ "$AWS_PROFILE_NAME" != "default" ] && CONFIG_SECTION="[profile ${AWS_PROFILE_NAME}]"
                cat >> "$HOME/.aws/config" <<EOF

${CONFIG_SECTION}
region = ${AWS_BEDROCK_REGION}
output = json
EOF
                success "AWS config written to ~/.aws/config"
            fi
        fi
        ;;
    sso)
        # Write SSO profile to ~/.aws/config
        CONFIG_SECTION="[${AWS_PROFILE_NAME}]"
        [ "$AWS_PROFILE_NAME" != "default" ] && CONFIG_SECTION="[profile ${AWS_PROFILE_NAME}]"
        
        # Remove existing profile section if present, then append
        if grep -q "\[.*${AWS_PROFILE_NAME}\]" "$HOME/.aws/config" 2>/dev/null; then
            cp "$HOME/.aws/config" "$HOME/.aws/config.bak.$(date +%s)"
            warn "已有 ${AWS_PROFILE_NAME} profile 已备份"
        fi
        
        cat >> "$HOME/.aws/config" <<EOF

${CONFIG_SECTION}
sso_start_url = ${AWS_SSO_START_URL}
sso_region = ${AWS_SSO_REGION}
sso_account_id = ${AWS_SSO_ACCOUNT_ID}
sso_role_name = ${AWS_SSO_ROLE_NAME}
region = ${AWS_BEDROCK_REGION}
output = json
EOF
        success "AWS SSO profile written to ~/.aws/config (profile: ${AWS_PROFILE_NAME})"
        
        echo ""
        echo -e "${YELLOW}${BOLD}接下来需要通过浏览器完成 SSO 登录：${NC}"
        echo -e "  系统会自动打开浏览器，请在浏览器中完成登录授权。"
        echo ""
        
        if command -v aws >/dev/null 2>&1; then
            aws sso login --profile "$AWS_PROFILE_NAME" || {
                warn "SSO 登录失败，请稍后手动运行: aws sso login --profile ${AWS_PROFILE_NAME}"
            }
        else
            warn "AWS CLI 尚未安装，SSO 登录将在安装 AWS CLI 后进行"
            SSO_LOGIN_PENDING=true
        fi
        ;;
    profile)
        info "使用已有 profile: ${AWS_PROFILE_NAME}"
        # Ensure region is set for the profile
        if command -v aws >/dev/null 2>&1; then
            CURRENT_REGION=$(aws configure get region --profile "$AWS_PROFILE_NAME" 2>/dev/null || echo "")
            if [ -z "$CURRENT_REGION" ]; then
                aws configure set region "$AWS_BEDROCK_REGION" --profile "$AWS_PROFILE_NAME"
                success "已为 profile ${AWS_PROFILE_NAME} 设置区域: ${AWS_BEDROCK_REGION}"
            else
                info "Profile ${AWS_PROFILE_NAME} 已有区域设置: ${CURRENT_REGION}"
            fi
        fi
        ;;
    skip)
        success "使用已有 AWS 配置"
        ;;
esac

# Set AWS_PROFILE env var if not default
if [ "$AWS_PROFILE_NAME" != "default" ]; then
    export AWS_PROFILE="$AWS_PROFILE_NAME"
fi

# --- Configure Claude Code for Bedrock ---
info "Configuring Claude Code for Bedrock..."

CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

PROFILE_PREFIX="us"
case "$CC_BEDROCK_REGION" in
    eu-*)  PROFILE_PREFIX="eu" ;;
    ap-*)  PROFILE_PREFIX="ap" ;;
esac

if [ -f "$CLAUDE_DIR/settings.json" ]; then
    cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak.$(date +%s)"
    warn "已有 settings.json 已备份为 settings.json.bak.*"
fi

# Build env block — add AWS_PROFILE if non-default, add SSO refresh if SSO mode
CLAUDE_ENV_EXTRA=""
if [ "$AWS_PROFILE_NAME" != "default" ]; then
    CLAUDE_ENV_EXTRA="$(printf '\n        "AWS_PROFILE": "%s",' "$AWS_PROFILE_NAME")"
fi
if [ "$AWS_AUTH_MODE" = "sso" ]; then
    CLAUDE_ENV_EXTRA="${CLAUDE_ENV_EXTRA}$(printf '\n        "CLAUDE_CODE_AWS_AUTH_REFRESH": "sso:%s",' "$AWS_PROFILE_NAME")"
fi

cat > "$CLAUDE_DIR/settings.json" <<SETTINGS_EOF
{
    "\$schema": "https://json.schemastore.org/claude-code-settings.json",
    "respectGitignore": true,
    "cleanupPeriodDays": 30,
    "env": {
        "CLAUDE_CODE_USE_BEDROCK": "1",
        "AWS_REGION": "${CC_BEDROCK_REGION}",${CLAUDE_ENV_EXTRA}
        "ANTHROPIC_MODEL": "${PROFILE_PREFIX}.anthropic.claude-opus-4-6-v1",
        "CLAUDE_CODE_SUBAGENT_MODEL": "${PROFILE_PREFIX}.anthropic.claude-sonnet-4-6",
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
        "CLAUDE_CODE_EFFORT_LEVEL": "medium",
        "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50",
        "CLAUDE_PACKAGE_MANAGER": "pnpm",
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1"
    },
    "model": "${PROFILE_PREFIX}.anthropic.claude-opus-4-6-v1",
    "permissions": {
        "allow": [
            "Bash",
            "mcp__plugin_context7_context7__*",
            "mcp__chrome-devtools__*",
            "mcp__playwright__*",
            "mcp__github__*",
            "mcp__filesystem__*",
            "mcp__sequential-thinking__*",
            "mcp__brave-search__*",
            "mcp__tavily__*",
            "mcp__docker__*",
            "mcp__aws-documentation__*",
            "WebFetch",
            "Write",
            "Edit"
        ],
        "deny": [
            "Bash(rm -rf /*)",
            "Bash(rm -rf /)",
            "Bash(rm -rf ~/*)",
            "Bash(rm -rf ~)",
            "Bash(sudo rm *)",
            "Bash(git push --force *)",
            "Bash(git reset --hard *)",
            "Bash(git clean -f*)",
            "Bash(mkfs*)",
            "Bash(dd if=*)"
        ]
    },
    "outputStyle": "Concise",
    "language": "chinese",
    "sandbox": {
        "enabled": false,
        "autoAllowBashIfSandboxed": true
    },
    "enabledPlugins": {
        "context7@claude-plugins-official": true,
        "everything-claude-code@everything-claude-code": true
    },
    "extraKnownMarketplaces": {
        "everything-claude-code": {
            "source": {
                "source": "github",
                "repo": "affaan-m/everything-claude-code"
            }
        }
    }
}
SETTINGS_EOF
success "Claude Code settings.json written"

if [ -f "$HOME/.mcp.json" ]; then
    cp "$HOME/.mcp.json" "$HOME/.mcp.json.bak.$(date +%s)"
    warn "已有 .mcp.json 已备份为 .mcp.json.bak.*"
fi

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
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": ""
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-filesystem@latest", "${HOME}/Documents", "${HOME}/Desktop", "${HOME}/.openclaw/workspace"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-sequential-thinking@latest"]
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "brave-search-mcp@latest"],
      "env": {
        "BRAVE_API_KEY": ""
      }
    },
    "tavily": {
      "command": "npx",
      "args": ["-y", "tavily-mcp@latest"],
      "env": {
        "TAVILY_API_KEY": ""
      }
    },
    "docker": {
      "command": "npx",
      "args": ["-y", "mcp-server-docker@latest"]
    },
    "aws-documentation": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR",
        "AWS_DOCUMENTATION_PARTITION": "aws"
      }
    }
  }
}
MCP_EOF
success "MCP servers config written to ~/.mcp.json"

echo ""
echo -e "${GREEN}${BOLD}Claude Code 已配置完成，可以随时使用！${NC}"
echo -e "如果后续步骤遇到问题，打开新终端窗口输入 ${CYAN}claude${NC} 让它帮你排查。"
echo ""

# ============================================================================
# Step 3: fnm (Fast Node Manager) + Node.js
# ============================================================================
step 3 "Install fnm + Node.js"

# fnm (Fast Node Manager)
if check_command fnm; then
    success "fnm already installed: $(fnm --version)"
else
    info "Installing fnm (Fast Node Manager)..."
    if curl -fsSL https://fnm.vercel.app/install | bash; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env 2>/dev/null)" || true
        success "fnm installed"
    else
        echo -e "${RED}fnm 安装失败。${NC}你可以打开新终端输入 ${GREEN}claude${NC} 让它帮你修，或手动运行: ${CYAN}curl -fsSL https://fnm.vercel.app/install | bash${NC}"
        exit 1
    fi
fi

# Ensure fnm is in PATH
eval "$(fnm env 2>/dev/null)" || true

# Node.js via fnm
if check_command node; then
    success "Node.js already installed: $(node --version)"
else
    info "Installing Node.js LTS via fnm..."
    if fnm install --lts && fnm use lts-latest && fnm default lts-latest; then
        eval "$(fnm env)"
        success "Node.js installed: $(node --version)"
    else
        echo -e "${RED}Node.js 安装失败。${NC}你可以打开新终端输入 ${GREEN}claude${NC} 让它帮你修，或手动运行: ${CYAN}fnm install --lts${NC}"
        exit 1
    fi
fi

# ============================================================================
# Step 4: Core dependencies (Node.js, pnpm, uv, AWS CLI, Chrome)
# ============================================================================
step 4 "Install core dependencies (pnpm, uv, AWS CLI)"

# pnpm (via corepack or npm fallback)
if check_command pnpm; then
    success "pnpm already installed: $(pnpm --version)"
else
    info "Installing pnpm..."
    if corepack enable 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null; then
        success "pnpm installed via corepack"
    elif npm install -g pnpm; then
        pnpm setup 2>/dev/null || true
        export PNPM_HOME="$HOME/Library/pnpm"
        export PATH="$PNPM_HOME:$PATH"
        success "pnpm installed via npm"
    else
        echo -e "${RED}pnpm 安装失败。${NC}你可以打开新终端输入 ${GREEN}claude${NC} 让它帮你修，或手动运行: ${CYAN}npm install -g pnpm${NC}"
        exit 1
    fi
fi

# uv (for Python MCP servers)
if check_command uv; then
    success "uv already installed: $(uv --version)"
else
    info "Installing uv (Python package manager)..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        success "uv installed"
    else
        echo -e "${RED}uv 安装失败。${NC}你可以打开新终端输入 ${GREEN}claude${NC} 让它帮你修，或手动运行: ${CYAN}curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
        exit 1
    fi
fi

# AWS CLI (official pkg installer)
if check_command aws; then
    success "AWS CLI already installed: $(aws --version 2>&1 | head -1)"
else
    info "Installing AWS CLI via official installer..."
    AWSCLI_TMP="/tmp/awscli-install-$$"
    mkdir -p "$AWSCLI_TMP"
    if curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$AWSCLI_TMP/AWSCLIV2.pkg" \
       && sudo installer -pkg "$AWSCLI_TMP/AWSCLIV2.pkg" -target /; then
        rm -rf "$AWSCLI_TMP"
        success "AWS CLI installed: $(aws --version 2>&1 | head -1)"
    else
        rm -rf "$AWSCLI_TMP"
        echo -e "${RED}AWS CLI 安装失败。${NC}你可以打开新终端输入 ${GREEN}claude${NC} 让它帮你修，或手动从 ${CYAN}https://awscli.amazonaws.com/AWSCLIV2.pkg${NC} 下载安装"
        exit 1
    fi
fi

# Google Chrome (needed for chrome-devtools MCP)
CHROME_APP="/Applications/Google Chrome.app"
if [ -d "$CHROME_APP" ]; then
    success "Google Chrome already installed"
else
    warn "未检测到 Google Chrome。Chrome DevTools MCP 需要 Chrome 才能工作。"
    echo -e "  请手动从 ${CYAN}https://www.google.com/chrome/${NC} 下载安装，然后重新运行本脚本。"
    echo -e "  ${YELLOW}安装会继续，但 Chrome 相关功能暂不可用。${NC}"
fi

# Complete pending SSO login (if AWS CLI was just installed)
if [ "${SSO_LOGIN_PENDING:-false}" = "true" ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}AWS CLI 已安装，现在完成 SSO 登录：${NC}"
    aws sso login --profile "$AWS_PROFILE_NAME" || {
        warn "SSO 登录失败，请稍后手动运行: aws sso login --profile ${AWS_PROFILE_NAME}"
    }
fi

# Verify AWS credentials (now that AWS CLI is available)
info "Verifying AWS credentials..."
AWS_VERIFY_ARGS=""
[ "$AWS_PROFILE_NAME" != "default" ] && AWS_VERIFY_ARGS="--profile $AWS_PROFILE_NAME"
if aws sts get-caller-identity $AWS_VERIFY_ARGS >/dev/null 2>&1; then
    success "AWS credentials valid: $(aws sts get-caller-identity $AWS_VERIFY_ARGS --query 'Account' --output text)"
else
    warn "AWS credential verification failed."
    if [ "$AWS_AUTH_MODE" = "sso" ]; then
        echo -e "  ${YELLOW}SSO 凭证可能已过期，请运行: ${CYAN}aws sso login --profile ${AWS_PROFILE_NAME}${NC}"
    else
        echo -e "  ${YELLOW}请检查 ~/.aws/credentials 配置是否正确${NC}"
    fi
fi

# Verify Bedrock endpoint
info "Verifying Bedrock endpoint in ${AWS_BEDROCK_REGION}..."
BEDROCK_TEST_PREFIX="us"
case "$AWS_BEDROCK_REGION" in
    eu-*)  BEDROCK_TEST_PREFIX="eu" ;;
    ap-*)  BEDROCK_TEST_PREFIX="ap" ;;
esac

BEDROCK_VERIFY_ARGS=""
[ "$AWS_PROFILE_NAME" != "default" ] && BEDROCK_VERIFY_ARGS="--profile $AWS_PROFILE_NAME"

if aws bedrock-runtime invoke-model \
    --model-id "${BEDROCK_TEST_PREFIX}.anthropic.claude-haiku-4-5-20251001-v1:0" \
    --region "$AWS_BEDROCK_REGION" \
    $BEDROCK_VERIFY_ARGS \
    --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}' \
    --content-type "application/json" \
    /dev/null >/dev/null 2>&1; then
    success "Bedrock endpoint verified in ${AWS_BEDROCK_REGION} (model accessible)"
else
    warn "Bedrock 权限检测失败（${AWS_BEDROCK_REGION}）"
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠ 你的 AWS 账号可能缺少 Bedrock 权限，Claude Code 和 OpenClaw 将无法正常工作。${NC}"
    echo ""
    echo -e "  ${BOLD}请检查以下几项：${NC}"
    echo ""
    echo -e "  ${CYAN}1. IAM 权限不足${NC}"
    echo -e "     → 给你的 IAM 用户附加策略 ${GREEN}AmazonBedrockFullAccess${NC}"
    echo -e "     → 或至少添加这 4 个权限："
    echo -e "       ${GREEN}bedrock:InvokeModel${NC}"
    echo -e "       ${GREEN}bedrock:InvokeModelWithResponseStream${NC}"
    echo -e "       ${GREEN}bedrock:ListFoundationModels${NC}"
    echo -e "       ${GREEN}bedrock:GetFoundationModel${NC}"
    echo ""
    echo -e "  ${CYAN}2. 模型访问未开启${NC}"
    echo -e "     → AWS Console → Bedrock → Model access → 勾选 ${GREEN}Anthropic Claude 全系列${NC} → Save"
    echo ""
    echo -e "  ${CYAN}3. 区域不支持 Bedrock${NC}"
    echo -e "     → 当前区域: ${YELLOW}${AWS_BEDROCK_REGION}${NC}"
    echo -e "     → 推荐使用: ${GREEN}us-west-2${NC}（美西）或 ${GREEN}us-east-1${NC}（美东）"
    echo ""
    echo -e "  ${GREEN}${BOLD}安装会继续，但请尽快修复权限，否则 Claude Code 和 OpenClaw 无法调用 AI 模型。${NC}"
    echo -e "  修复后可以打开新终端输入 ${CYAN}claude${NC} 验证是否正常工作。"
    echo ""
fi

# ============================================================================
# Step 4.5: Ensure PATH is persistent in shell rc files
# ============================================================================
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"
touch "$ZSHRC"

add_to_rc() {
    local line="$1"
    # Add to zshrc (macOS default)
    grep -qxF "$line" "$ZSHRC" 2>/dev/null || echo "$line" >> "$ZSHRC"
    # Also add to bashrc if it exists (for bash users / Linux compat)
    if [ -f "$BASHRC" ]; then
        grep -qxF "$line" "$BASHRC" 2>/dev/null || echo "$line" >> "$BASHRC"
    fi
}

add_to_rc '# fnm (Fast Node Manager)'
add_to_rc 'eval "$(fnm env 2>/dev/null)"'
add_to_rc '# pnpm'
add_to_rc 'export PNPM_HOME="$HOME/Library/pnpm"'
add_to_rc 'export PATH="$PNPM_HOME:$PATH"'
add_to_rc '# uv / Claude Code / local bin'
add_to_rc 'export PATH="$HOME/.local/bin:$PATH"'

# Persist AWS_PROFILE if non-default
if [ "$AWS_PROFILE_NAME" != "default" ]; then
    add_to_rc "# AWS profile for OneClaw/Bedrock"
    add_to_rc "export AWS_PROFILE=\"${AWS_PROFILE_NAME}\""
fi

success "PATH 配置已写入 shell rc 文件（新终端窗口自动生效）"

# ============================================================================
# Step 5: Install OpenClaw
# ============================================================================
step 5 "Install OpenClaw"

if check_command openclaw; then
    success "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'installed')"
else
    info "Installing OpenClaw..."
    if curl -fsSL https://openclaw.ai/install.sh | bash; then
        export PATH="$HOME/Library/pnpm:$HOME/.local/bin:$PATH"
        hash -r 2>/dev/null || true
        if check_command openclaw; then
            success "OpenClaw installed"
        else
            warn "OpenClaw 已安装但未在 PATH 中。请稍后打开新终端窗口再试。"
        fi
    else
        echo -e "${RED}OpenClaw 安装失败。请手动运行: ${CYAN}curl -fsSL https://openclaw.ai/install.sh | bash${NC}"
        exit 1
    fi
fi

# ============================================================================
# Step 6: Configure OpenClaw
# ============================================================================
step 6 "Configure OpenClaw"

OPENCLAW_DIR="$HOME/.openclaw"
mkdir -p "$OPENCLAW_DIR/logs"
mkdir -p "$OPENCLAW_DIR/scripts"
mkdir -p "$OPENCLAW_DIR/workspace"

# Determine OpenClaw Bedrock model prefix (must match region)
OC_MODEL_PREFIX="us"
case "$AWS_BEDROCK_REGION" in
    eu-*)  OC_MODEL_PREFIX="eu" ;;
    ap-*)  OC_MODEL_PREFIX="ap" ;;
esac

# Backup existing OpenClaw config if present
if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    cp "$OPENCLAW_DIR/openclaw.json" "$OPENCLAW_DIR/openclaw.json.bak.$(date +%s)"
    warn "已有 openclaw.json 已备份为 openclaw.json.bak.*"
fi

# openclaw.json — minimal but complete
cat > "$OPENCLAW_DIR/openclaw.json" <<OC_EOF
{
  "browser": {
    "enabled": true,
    "headless": false,
    "noSandbox": false,
    "defaultProfile": "default-chrome",
    "profiles": {
      "default-chrome": {
        "cdpPort": 9222,
        "color": "#4285F4"
      }
    }
  },
  "acp": {
    "enabled": true,
    "defaultAgent": "claude-code",
    "allowedAgents": ["claude-code"],
    "maxConcurrentSessions": 3
  },
  "models": {
    "mode": "merge",
    "providers": {
      "amazon-bedrock": {
        "baseUrl": "https://bedrock-runtime.${AWS_BEDROCK_REGION}.amazonaws.com",
        "auth": "aws-sdk",
        "api": "bedrock-converse-stream",
        "models": [
          {
            "id": "${OC_MODEL_PREFIX}.anthropic.claude-opus-4-6-v1",
            "name": "Opus 4.6",
            "api": "bedrock-converse-stream",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": { "input": 5, "output": 25, "cacheRead": 0.5, "cacheWrite": 10 },
            "contextWindow": 200000,
            "maxTokens": 131072
          },
          {
            "id": "${OC_MODEL_PREFIX}.anthropic.claude-sonnet-4-6",
            "name": "Sonnet 4.6",
            "api": "bedrock-converse-stream",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 6 },
            "contextWindow": 200000,
            "maxTokens": 65536
          },
          {
            "id": "${OC_MODEL_PREFIX}.anthropic.claude-haiku-4-5-20251001-v1:0",
            "name": "Haiku 4.5",
            "api": "bedrock-converse-stream",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 1, "output": 5, "cacheRead": 0.1, "cacheWrite": 2 },
            "contextWindow": 200000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "amazon-bedrock/${OC_MODEL_PREFIX}.anthropic.claude-sonnet-4-6"
      },
      "workspace": "${OPENCLAW_DIR}/workspace",
      "bootstrapMaxChars": 40000,
      "bootstrapTotalMaxChars": 200000,
      "cliBackends": {
        "claude-code": {
          "command": "${HOME}/.local/bin/claude",
          "args": ["--dangerously-skip-permissions", "-p", "--output-format", "stream-json"],
          "output": "jsonl",
          "input": "arg",
          "sessionMode": "always"
        }
      },
      "contextPruning": { "mode": "cache-ttl", "ttl": "1h" },
      "thinkingDefault": "medium",
      "heartbeat": { "every": "30m" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    },
    "list": [
      {
        "id": "main",
        "default": true,
        "name": "Assistant"
      }
    ]
  },
  "tools": {
    "exec": {
      "host": "gateway",
      "security": "full",
      "ask": "off"
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "controlUi": { "allowInsecureAuth": false },
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    },
    "tailscale": { "mode": "off" }
  },
  "skills": {
    "install": { "nodeManager": "pnpm" }
  },
  "plugins": {
    "entries": {
      "acpx": { "enabled": true }
    }
  }
}
OC_EOF
success "OpenClaw config written to ~/.openclaw/openclaw.json"

# Workspace markdown files — leave empty templates
for md_file in AGENTS.md SOUL.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md MEMORY.md; do
    if [ ! -f "$OPENCLAW_DIR/workspace/$md_file" ]; then
        touch "$OPENCLAW_DIR/workspace/$md_file"
    fi
done

# Memory system directories
mkdir -p "$OPENCLAW_DIR/workspace/memory/logs"
mkdir -p "$OPENCLAW_DIR/workspace/memory/projects"
mkdir -p "$OPENCLAW_DIR/workspace/memory/groups"
success "Workspace + memory system created"

# Install skill-vetter from ClawHub (security skill for vetting other skills)
info "安装 skill-vetter（技能安全审查工具）..."
mkdir -p "$OPENCLAW_DIR/skills"
npx clawhub install spclaudehome/skill-vetter --dir "$OPENCLAW_DIR/skills" 2>/dev/null \
    && success "skill-vetter 已安装" \
    || warn "skill-vetter 安装失败，可稍后手动安装：npx clawhub install spclaudehome/skill-vetter"

# Install OneClaw bundled skills (claude-code, aws-infra, chrome-devtools, skill-vetting)
info "安装 OneClaw 预置 Skills..."
SKILLS_DIR="$OPENCLAW_DIR/workspace/skills"
mkdir -p "$SKILLS_DIR"
ONECLAW_TMP="/tmp/oneclaw-skills-$$"
if git clone --depth 1 https://github.com/cncoder/oneclaw.git "$ONECLAW_TMP" 2>/dev/null; then
    for skill_name in claude-code aws-infra chrome-devtools skill-vetting architecture-svg; do
        if [ -d "$ONECLAW_TMP/skills/$skill_name" ]; then
            cp -r "$ONECLAW_TMP/skills/$skill_name" "$SKILLS_DIR/"
            success "Skill 已安装: $skill_name"
        fi
    done
    rm -rf "$ONECLAW_TMP"
else
    warn "Skills 自动安装失败（网络问题？），可稍后手动安装。"
    echo -e "  打开终端输入 ${GREEN}claude${NC}，然后说：「帮我安装 OneClaw skills」"
fi

# Install best community skills from ClawHub
info "安装社区推荐 Skills..."
CLAWHUB_SKILLS=(
    # Messaging bridges
    "openclaw/skills/feishu-bridge"
    "openclaw/skills/wecom"
    # Browser automation
    "openclaw/skills/playwright-cli"
    "openclaw/skills/clawbrowser"
    # System
    "openclaw/skills/clawhub"
    "openclaw/skills/memory-setup"
    "openclaw/skills/auto-updater"
)

# Add optional channel skills based on user choices
if [[ "${INSTALL_WECHAT:-N}" =~ ^[Yy] ]]; then
    CLAWHUB_SKILLS+=("aaaaqwq/agi-super-skills/wechat-channel")
fi
for skill_slug in "${CLAWHUB_SKILLS[@]}"; do
    skill_short="${skill_slug##*/}"
    npx clawhub install "$skill_slug" --dir "$OPENCLAW_DIR/skills" 2>/dev/null \
        && success "ClawHub skill 已安装: $skill_short" \
        || warn "ClawHub skill 安装失败: $skill_short（可稍后手动安装）"
done

# ============================================================================
# Step 7: Guardian watchdog script
# ============================================================================
step 7 "Set up Guardian watchdog"

cat > "$OPENCLAW_DIR/scripts/guardian-check.sh" <<'GUARDIAN_EOF'
#!/bin/bash
# guardian-check.sh — OpenClaw Gateway health check + auto-repair
# Called every 60s by ai.openclaw.guardian LaunchAgent
# Three layers: process alive → HTTP port → openclaw status

set -euo pipefail

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_HOST="127.0.0.1"
HEALTH_URL="http://${GATEWAY_HOST}:${GATEWAY_PORT}/"
STATE_FILE="/tmp/openclaw-guardian-state.json"
LOG_FILE="${HOME}/.openclaw/logs/guardian.log"
MAX_REPAIR=3
COOLDOWN_SECONDS=300
DISCORD_WEBHOOK="${DISCORD_WEBHOOK_URL:-}"

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $1" >> "$LOG_FILE"
}

notify() {
    local msg="$1"
    log "[NOTIFY] $msg"
    if [ -n "$DISCORD_WEBHOOK" ]; then
        curl -s -m 10 -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"🦞 **OpenClaw Guardian**: $msg\"}" \
            >/dev/null 2>&1 || true
    fi
}

read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"failures":0,"last_repair":0,"cooldown_until":0}'
    fi
}

write_state() {
    local failures="$1" last_repair="$2" cooldown_until="$3"
    cat > "$STATE_FILE" <<EOF
{"failures":${failures},"last_repair":${last_repair},"cooldown_until":${cooldown_until}}
EOF
}

get_field() {
    local json="$1" field="$2"
    python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('$field',0))" <<< "$json"
}

check_process() {
    launchctl list ai.openclaw.node >/dev/null 2>&1
}

check_http() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "$HEALTH_URL" 2>/dev/null || echo "000")
    [ "$code" = "200" ]
}

check_status() {
    local output
    output=$(openclaw status 2>&1 || true)
    echo "$output" | grep -qi "reachable\|running\|online"
}

try_repair() {
    log "Starting doctor --fix repair..."
    openclaw doctor --fix --non-interactive >> "$LOG_FILE" 2>&1 || true
    sleep 5

    if ! check_process; then
        log "Process not running, attempting kickstart..."
        launchctl kickstart -k "gui/$(id -u)/ai.openclaw.node" >> "$LOG_FILE" 2>&1 || true
        sleep 10
    fi
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    local now
    now=$(date +%s)

    local state
    state=$(read_state)
    local failures cooldown_until
    failures=$(get_field "$state" "failures")
    cooldown_until=$(get_field "$state" "cooldown_until")
    : "${failures:=0}"
    : "${cooldown_until:=0}"

    if [ "$now" -lt "$cooldown_until" ]; then
        log "In cooldown, skipping check (remaining $((cooldown_until - now))s)"
        exit 0
    fi

    local healthy=true
    local fail_layer=""

    if ! check_process; then
        healthy=false
        fail_layer="process"
    elif ! check_http; then
        healthy=false
        fail_layer="http"
    elif ! check_status; then
        healthy=false
        fail_layer="status"
    fi

    if [ "$healthy" = true ]; then
        if [ "$failures" -gt 0 ]; then
            log "Gateway recovered, resetting failure count (was ${failures})"
            write_state 0 0 0
        fi
        exit 0
    fi

    failures=$((failures + 1))
    log "Health check failed [layer=${fail_layer}] (consecutive failure #${failures})"

    if [ "$failures" -le "$MAX_REPAIR" ]; then
        try_repair

        if check_http; then
            log "Repair successful! Gateway recovered"
            notify "Gateway issue (${fail_layer}) → doctor --fix repair succeeded (attempt ${failures})"
            write_state 0 "$now" 0
        else
            log "Still unhealthy after repair (${failures}/${MAX_REPAIR})"
            write_state "$failures" "$now" 0
        fi
    else
        local cooldown_end=$((now + COOLDOWN_SECONDS))
        log "Max repairs (${MAX_REPAIR}) exceeded, entering ${COOLDOWN_SECONDS}s cooldown"
        notify "⚠️ Gateway persistent failure (${fail_layer}), doctor --fix failed ${MAX_REPAIR} times. Cooldown ${COOLDOWN_SECONDS}s. Manual intervention needed."
        write_state "$failures" "$now" "$cooldown_end"
    fi
}

main "$@"
GUARDIAN_EOF
chmod +x "$OPENCLAW_DIR/scripts/guardian-check.sh"
success "Guardian script written"

# --- Log rotation (macOS) ---
LOGROTATE_CONF="$OPENCLAW_DIR/scripts/logrotate.conf"
cat > "$LOGROTATE_CONF" <<'LOGROTATE_EOF'
# OneClaw log rotation — sourced by guardian-check.sh
# Rotates logs > 10MB, keeps 7 copies
LOGROTATE_EOF

cat > "$OPENCLAW_DIR/scripts/rotate-logs.sh" <<'ROTATE_EOF'
#!/bin/bash
# rotate-logs.sh — Simple log rotation for macOS (no logrotate available)
LOG_DIR="${HOME}/.openclaw/logs"
MAX_SIZE=$((10 * 1024 * 1024))  # 10MB
KEEP=7

for logfile in "$LOG_DIR"/*.log; do
    [ -f "$logfile" ] || continue
    size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_SIZE" ]; then
        for i in $(seq $((KEEP-1)) -1 1); do
            [ -f "${logfile}.${i}" ] && mv "${logfile}.${i}" "${logfile}.$((i+1))"
        done
        cp "$logfile" "${logfile}.1"
        : > "$logfile"
    fi
    # Remove old rotated logs
    for old in "${logfile}".$(( KEEP + 1 )) "${logfile}".$(( KEEP + 2 )); do
        rm -f "$old"
    done
done
ROTATE_EOF
chmod +x "$OPENCLAW_DIR/scripts/rotate-logs.sh"
success "Log rotation script created"

# ============================================================================
# Step 8: LaunchAgents (auto-start on boot)
# ============================================================================
step 8 "Set up LaunchAgents for auto-start"

LAUNCH_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_DIR"

# Find openclaw install path
OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "$HOME/Library/pnpm/openclaw")
if [ ! -x "$OPENCLAW_BIN" ]; then
    # Try common fallback locations
    for candidate in "$HOME/.local/bin/openclaw" "$HOME/Library/pnpm/openclaw"; do
        if [ -x "$candidate" ]; then
            OPENCLAW_BIN="$candidate"
            break
        fi
    done
fi

# Build PATH string for LaunchAgents
LAUNCH_PATH="$HOME/.local/bin:$HOME/Library/pnpm:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Gateway plist
cat > "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.gateway</string>
    <key>ProgramArguments</key>
    <array>
        <string>${OPENCLAW_BIN}</string>
        <string>gateway</string>
        <string>--port</string>
        <string>18789</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${LAUNCH_PATH}</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>18789</string>
        <key>OPENCLAW_GATEWAY_TOKEN</key>
        <string>${GATEWAY_TOKEN}</string>
PLIST_EOF

# Add Discord bot token if provided
if [ -n "$DISCORD_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_DISCORD
        <key>DISCORD_BOT_TOKEN</key>
        <string>${DISCORD_BOT_TOKEN}</string>
PLIST_DISCORD
fi

# Add Lark/Feishu credentials if provided
if [ -n "$LARK_APP_ID" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_LARK
        <key>LARK_APP_ID</key>
        <string>${LARK_APP_ID}</string>
        <key>LARK_APP_SECRET</key>
        <string>${LARK_APP_SECRET}</string>
PLIST_LARK
fi

# Add Telegram bot token if provided
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_TG
        <key>TELEGRAM_BOT_TOKEN</key>
        <string>${TELEGRAM_BOT_TOKEN}</string>
PLIST_TG
fi

# Add Slack bot token if provided
if [ -n "$SLACK_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_SLACK
        <key>SLACK_BOT_TOKEN</key>
        <string>${SLACK_BOT_TOKEN}</string>
PLIST_SLACK
fi

# Add WeCom credentials if provided
if [ -n "$WECOM_CORP_ID" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_WECOM
        <key>WECOM_CORP_ID</key>
        <string>${WECOM_CORP_ID}</string>
        <key>WECOM_AGENT_ID</key>
        <string>${WECOM_AGENT_ID}</string>
        <key>WECOM_SECRET</key>
        <string>${WECOM_SECRET}</string>
PLIST_WECOM
fi
if [ -n "$WECOM_WEBHOOK_URL" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_WECOM_WH
        <key>WECOM_WEBHOOK_URL</key>
        <string>${WECOM_WEBHOOK_URL}</string>
PLIST_WECOM_WH
fi

cat >> "$LAUNCH_DIR/ai.openclaw.gateway.plist" <<PLIST_TAIL
    </dict>
    <key>StandardOutPath</key>
    <string>${OPENCLAW_DIR}/logs/gateway.log</string>
    <key>StandardErrorPath</key>
    <string>${OPENCLAW_DIR}/logs/gateway.err.log</string>
</dict>
</plist>
PLIST_TAIL
success "Gateway LaunchAgent created"

# Node plist
cat > "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.node</string>
    <key>ProgramArguments</key>
    <array>
        <string>${OPENCLAW_BIN}</string>
        <string>node</string>
        <string>run</string>
        <string>--host</string>
        <string>127.0.0.1</string>
        <string>--port</string>
        <string>18789</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${LAUNCH_PATH}</string>
        <key>HOME</key>
        <string>${HOME}</string>
PLIST_EOF

if [ -n "$DISCORD_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_DISCORD
        <key>DISCORD_BOT_TOKEN</key>
        <string>${DISCORD_BOT_TOKEN}</string>
PLIST_DISCORD
fi

if [ -n "$LARK_APP_ID" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_LARK2
        <key>LARK_APP_ID</key>
        <string>${LARK_APP_ID}</string>
        <key>LARK_APP_SECRET</key>
        <string>${LARK_APP_SECRET}</string>
PLIST_LARK2
fi

if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_TG2
        <key>TELEGRAM_BOT_TOKEN</key>
        <string>${TELEGRAM_BOT_TOKEN}</string>
PLIST_TG2
fi

if [ -n "$SLACK_BOT_TOKEN" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_SLACK2
        <key>SLACK_BOT_TOKEN</key>
        <string>${SLACK_BOT_TOKEN}</string>
PLIST_SLACK2
fi

if [ -n "$WECOM_CORP_ID" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_WECOM2
        <key>WECOM_CORP_ID</key>
        <string>${WECOM_CORP_ID}</string>
        <key>WECOM_AGENT_ID</key>
        <string>${WECOM_AGENT_ID}</string>
        <key>WECOM_SECRET</key>
        <string>${WECOM_SECRET}</string>
PLIST_WECOM2
fi

cat >> "$LAUNCH_DIR/ai.openclaw.node.plist" <<PLIST_TAIL
    </dict>
    <key>StandardOutPath</key>
    <string>${OPENCLAW_DIR}/logs/node.log</string>
    <key>StandardErrorPath</key>
    <string>${OPENCLAW_DIR}/logs/node.err.log</string>
</dict>
</plist>
PLIST_TAIL
success "Node LaunchAgent created"

# Guardian plist (every 60s health check)
cat > "$LAUNCH_DIR/ai.openclaw.guardian.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.guardian</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${OPENCLAW_DIR}/scripts/guardian-check.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${LAUNCH_PATH}</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>18789</string>
PLIST_EOF

if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    cat >> "$LAUNCH_DIR/ai.openclaw.guardian.plist" <<PLIST_WEBHOOK
        <key>DISCORD_WEBHOOK_URL</key>
        <string>${DISCORD_WEBHOOK_URL}</string>
PLIST_WEBHOOK
fi

cat >> "$LAUNCH_DIR/ai.openclaw.guardian.plist" <<PLIST_TAIL
    </dict>
    <key>StandardOutPath</key>
    <string>${OPENCLAW_DIR}/logs/guardian-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${OPENCLAW_DIR}/logs/guardian-stderr.log</string>
</dict>
</plist>
PLIST_TAIL
success "Guardian LaunchAgent created"

# Chrome CDP plist (auto-start Chrome with remote debugging on port 9222)
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CHROME_DATA_DIR="${HOME}/.openclaw/chrome-profile"
mkdir -p "$CHROME_DATA_DIR"

cat > "$LAUNCH_DIR/ai.openclaw.chrome.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.chrome</string>
    <key>ProgramArguments</key>
    <array>
        <string>${CHROME_BIN}</string>
        <string>--remote-debugging-port=9222</string>
        <string>--user-data-dir=${CHROME_DATA_DIR}</string>
        <string>--no-first-run</string>
        <string>--no-default-browser-check</string>
    </array>
    <key>KeepAlive</key>
    <false/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${OPENCLAW_DIR}/logs/chrome-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${OPENCLAW_DIR}/logs/chrome-stderr.log</string>
</dict>
</plist>
PLIST_EOF
success "Chrome CDP LaunchAgent created (port 9222)"

# ============================================================================
# Step 9: Generate CLAUDE.md for OpenClaw init
# ============================================================================
step 9 "Generate CLAUDE.md for OpenClaw initialization"

cat > "$OPENCLAW_DIR/workspace/CLAUDE.md" <<'CLAUDEMD_EOF'
# OpenClaw Workspace

## System

This is an OpenClaw-managed workspace running on Amazon Bedrock (Claude models).
Memory is persistent — files in this workspace survive restarts.

## Rules

- Always respond in the user's preferred language
- Be concise and helpful
- For code tasks: read before edit, verify after change
- Never delete files directly — move to trash instead
- When unsure, ask for clarification
- Write important context to MEMORY.md for future sessions
- Check MEMORY.md at the start of each session for context

## Memory System

- **MEMORY.md** — Long-term facts, preferences, project context
- **memory/logs/** — Daily interaction logs (auto-created)
- **memory/projects/** — Per-project notes
- Use `memorySearch` to find past context when needed

## Tools Available

- **Claude Code**: Full coding agent (via ACP)
- **Browser**: Chrome DevTools (port 9222) + Playwright
- **Shell**: Execute system commands
- **GitHub**: PR/Issue management via MCP
- **Filesystem**: Safe local file access via MCP
- **Sequential Thinking**: Complex reasoning chains
- **Brave Search**: Web search via MCP
- **AWS Docs**: AWS documentation queries

## Self-Maintenance

- Run `openclaw doctor` to diagnose issues
- Skills auto-update daily via auto-updater skill
- Check `openclaw status` for service health
- Guardian daemon monitors every 60s

## Quick Start

- Control UI: http://127.0.0.1:18789
- Terminal: `openclaw chat`
- Channels: Discord, Telegram, Slack, Lark, WeCom, WeChat, WhatsApp
CLAUDEMD_EOF
success "CLAUDE.md written"

# ============================================================================
# Step 10: Start services
# ============================================================================
step 10 "Start OpenClaw services"

# Unload first in case they exist
la_unload "$LAUNCH_DIR/ai.openclaw.chrome.plist"
la_unload "$LAUNCH_DIR/ai.openclaw.gateway.plist"
la_unload "$LAUNCH_DIR/ai.openclaw.node.plist"
la_unload "$LAUNCH_DIR/ai.openclaw.guardian.plist"

sleep 1

# Start Chrome CDP first (MCP servers depend on it)
la_load "$LAUNCH_DIR/ai.openclaw.chrome.plist"
info "Chrome CDP LaunchAgent loaded (port 9222)"

sleep 2

# Load and start OpenClaw services
la_load "$LAUNCH_DIR/ai.openclaw.gateway.plist"
info "Gateway LaunchAgent loaded"

sleep 3

la_load "$LAUNCH_DIR/ai.openclaw.node.plist"
info "Node LaunchAgent loaded"

sleep 2

la_load "$LAUNCH_DIR/ai.openclaw.guardian.plist"
info "Guardian LaunchAgent loaded"

# Wait for gateway to come up
info "Waiting for gateway to start..."
for i in $(seq 1 15); do
    if curl -s -o /dev/null -w "%{http_code}" -m 2 "http://127.0.0.1:18789/" 2>/dev/null | grep -q "200"; then
        success "Gateway is running on port 18789!"
        break
    fi
    sleep 2
    [ "$i" -eq 15 ] && warn "Gateway not responding yet. Check logs: ~/.openclaw/logs/gateway.log"
done

# ============================================================================
# Step 11: Smoke test
# ============================================================================
step 11 "验证安装"

SMOKE_PASS=0
SMOKE_FAIL=0

smoke_check() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        success "$name"
        SMOKE_PASS=$((SMOKE_PASS + 1))
    else
        warn "$name — 未通过（可稍后手动检查）"
        SMOKE_FAIL=$((SMOKE_FAIL + 1))
    fi
}

smoke_check "AWS CLI 可用" "aws --version"
smoke_check "Claude Code 可用" "claude --version"
smoke_check "OpenClaw 可用" "openclaw --version"
smoke_check "Gateway 端口响应" "curl -s -m 3 http://127.0.0.1:18789/ -o /dev/null"
smoke_check "AWS 凭证有效" "aws sts get-caller-identity ${AWS_VERIFY_ARGS:-}"

info "冒烟测试结果：${SMOKE_PASS} 通过，${SMOKE_FAIL} 未通过"
if [ "$SMOKE_FAIL" -gt 0 ]; then
    warn "有未通过的检查项，但不影响大部分功能。可以先继续使用，后续再排查。"
fi

# ============================================================================
# Step 12: Repair script for emergencies
# ============================================================================
step 12 "创建紧急修复脚本"

cat > "$OPENCLAW_DIR/scripts/repair.sh" <<'REPAIR_EOF'
#!/bin/bash
# repair.sh — Emergency repair for OpenClaw
# Double-click in ~/Documents/OneClaw/, or run: bash ~/Documents/OneClaw/repair.command

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${CYAN}${BOLD}=== OpenClaw Emergency Repair ===${NC}\n"

_GUI_UID=$(id -u)
_la_load() {
    local plist="$1" label
    label=$(basename "$plist" .plist)
    if [ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 13 ] 2>/dev/null; then
        launchctl bootstrap "gui/${_GUI_UID}" "$plist" 2>/dev/null || \
            launchctl kickstart -k "gui/${_GUI_UID}/${label}" 2>/dev/null || true
    else
        launchctl load "$plist" 2>/dev/null || true
    fi
}
_la_unload() {
    local plist="$1" label
    label=$(basename "$plist" .plist)
    if [ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 13 ] 2>/dev/null; then
        launchctl bootout "gui/${_GUI_UID}/${label}" 2>/dev/null || true
    else
        launchctl unload "$plist" 2>/dev/null || true
    fi
}

echo -e "${YELLOW}[1/5] Stopping all services...${NC}"
_la_unload ~/Library/LaunchAgents/ai.openclaw.chrome.plist
_la_unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
_la_unload ~/Library/LaunchAgents/ai.openclaw.node.plist
_la_unload ~/Library/LaunchAgents/ai.openclaw.guardian.plist
pkill -f "openclaw gateway" 2>/dev/null || true
pkill -f "openclaw node" 2>/dev/null || true
sleep 2

echo -e "${YELLOW}[2/5] Clearing state files...${NC}"
rm -f /tmp/openclaw-guardian-state.json

echo -e "${YELLOW}[3/5] Running openclaw doctor --fix...${NC}"
openclaw doctor --fix --non-interactive 2>&1 || true
sleep 2

echo -e "${YELLOW}[4/5] Restarting services...${NC}"
_la_load ~/Library/LaunchAgents/ai.openclaw.chrome.plist
sleep 2
_la_load ~/Library/LaunchAgents/ai.openclaw.gateway.plist
sleep 3
_la_load ~/Library/LaunchAgents/ai.openclaw.node.plist
sleep 2
_la_load ~/Library/LaunchAgents/ai.openclaw.guardian.plist

echo -e "${YELLOW}[5/5] Waiting for gateway...${NC}"
for i in $(seq 1 15); do
    if curl -s -o /dev/null -m 2 "http://127.0.0.1:18789/" 2>/dev/null; then
        echo -e "\n${GREEN}${BOLD}Gateway is back online!${NC}"
        echo -e "Control panel: ${CYAN}http://127.0.0.1:18789${NC}\n"
        exit 0
    fi
    sleep 2
done

echo -e "\n${RED}${BOLD}Gateway still not responding.${NC}"
echo -e "Try the AI repair command (copy-paste into terminal):\n"
echo -e "  ${CYAN}bash ~/Documents/OneClaw/ai-repair.command${NC}\n"
echo -e "Or check logs manually:"
echo "  tail -50 ~/.openclaw/logs/gateway.log"
echo "  tail -50 ~/.openclaw/logs/gateway.err.log"
REPAIR_EOF
chmod +x "$OPENCLAW_DIR/scripts/repair.sh"

# Copy repair.sh to ~/Documents/OneClaw/ for easy access
mkdir -p "$HOME/Documents/OneClaw"
cp "$OPENCLAW_DIR/scripts/repair.sh" "$HOME/Documents/OneClaw/repair.command"
chmod +x "$HOME/Documents/OneClaw/repair.command"
success "Repair script created: ~/Documents/OneClaw/repair.command"

# ============================================================================
# Step 12.5: AI-powered repair script (Claude Code --dangerously-skip-permissions)
# ============================================================================
info "Creating AI-powered repair script..."

cat > "$OPENCLAW_DIR/scripts/ai-repair.sh" <<'AIREPAIR_EOF'
#!/bin/bash
# ai-repair.sh — Let Claude Code diagnose and fix OpenClaw automatically
# Usage: bash ~/.openclaw/scripts/ai-repair.sh
#   or:  bash ~/Documents/OneClaw/ai-repair.command

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${CYAN}${BOLD}=== OpenClaw AI Repair (Claude Code) ===${NC}"
echo -e "${YELLOW}Claude Code will automatically diagnose and fix OpenClaw issues.${NC}"
echo -e "This may take 1-3 minutes...\n"

# Check Claude Code is available
if ! command -v claude >/dev/null 2>&1; then
    echo -e "${RED}Claude Code not found. Please run: source ~/.zshrc${NC}"
    exit 1
fi

# Build the diagnostic prompt with all context Claude needs
REPAIR_PROMPT='You are an OpenClaw repair agent. Diagnose and fix the issue step by step.

## System Layout
- Config: ~/.openclaw/openclaw.json
- Logs: ~/.openclaw/logs/ (gateway.log, gateway.err.log, node.log, node.err.log, guardian.log, chrome-stdout.log)
- LaunchAgents: ~/Library/LaunchAgents/ai.openclaw.{gateway,node,guardian,chrome}.plist
- Scripts: ~/.openclaw/scripts/
- AWS creds: ~/.aws/credentials, ~/.aws/config
- Claude Code: ~/.claude/settings.json, ~/.mcp.json

## Diagnostic Steps (DO ALL OF THESE)
1. Run `openclaw status` to get current state
2. Run `openclaw doctor` to check health
3. Check recent errors: `tail -80 ~/.openclaw/logs/gateway.err.log` and `tail -80 ~/.openclaw/logs/node.err.log`
4. Check LaunchAgent status: `launchctl list | grep openclaw`
5. Check if ports are in use: `lsof -i :18789` and `lsof -i :9222`
6. Verify AWS credentials: `aws sts get-caller-identity`

## Common Issues & Fixes
- Gateway not starting → check port conflict, check logs, restart LaunchAgent
- Node not connecting → check gateway is up first, verify token in plist matches openclaw.json
- Chrome CDP not responding → restart Chrome LaunchAgent, check port 9222
- AWS auth failure → check ~/.aws/credentials format
- "already running" errors → kill orphan processes first: `pkill -f "openclaw gateway"; pkill -f "openclaw node"`
- Permission errors → check file ownership with `ls -la ~/.openclaw/`

## Repair Actions
After diagnosis, fix the root cause. Then restart services in order:
1. Stop services (macOS 13+: `launchctl bootout gui/$(id -u)/ai.openclaw.chrome` etc., older: `launchctl unload ~/Library/LaunchAgents/ai.openclaw.*.plist`)
2. Kill orphans: `pkill -f "openclaw gateway"; pkill -f "openclaw node"`
3. Start Chrome: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.chrome.plist` → wait 2s
4. Start Gateway: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist` → wait 3s
5. Start Node: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.node.plist` → wait 2s
6. Start Guardian: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.guardian.plist`
7. Verify: `curl -s http://127.0.0.1:18789/` should return 200

## Output
Print a clear summary of what you found and what you fixed. Use Chinese.'

# Run Claude Code in dangerously-skip-permissions mode with the prompt
claude --dangerously-skip-permissions -p "$REPAIR_PROMPT" --output-format text 2>&1

echo -e "\n${GREEN}${BOLD}AI repair complete.${NC}"
echo -e "If issues persist, check: ${CYAN}https://github.com/cncoder/oneclaw/issues${NC}\n"
AIREPAIR_EOF
chmod +x "$OPENCLAW_DIR/scripts/ai-repair.sh"

# Copy to ~/Documents/OneClaw/ too
mkdir -p "$HOME/Documents/OneClaw"
cp "$OPENCLAW_DIR/scripts/ai-repair.sh" "$HOME/Documents/OneClaw/ai-repair.command"
chmod +x "$HOME/Documents/OneClaw/ai-repair.command"
success "AI repair script created: ~/Documents/OneClaw/ai-repair.command"

# open-claude.command — one-click open Claude Code interactive mode
cat > "$HOME/Documents/OneClaw/open-claude.command" <<'ASKCLAUDE_EOF'
#!/bin/bash
# open-claude.command — Open Claude Code in interactive mode
# Double-click this file to start chatting with Claude in Chinese.

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/Library/pnpm:/usr/local/bin:$PATH"
eval "$(fnm env 2>/dev/null)" || true

if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code not found. Please run: source ~/.zshrc"
    exit 1
fi

# Step 1: Auto-restore missing shortcuts (silent, ~30s)
ONECLAW_DIR="$HOME/Documents/OneClaw"
NEED_RESTORE=false
[ ! -f "$ONECLAW_DIR/ai-repair.command" ] && NEED_RESTORE=true
[ ! -f "$ONECLAW_DIR/repair.command" ] && NEED_RESTORE=true

if [ "$NEED_RESTORE" = "true" ]; then
    echo ""
    echo "  检测到快捷方式缺失，正在自动补全..."
    RESTORE_PROMPT='请立即按顺序执行以下操作，不要询问确认：

第一步：运行修复脚本
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/fix.sh)"

第二步：确认结果
检查 ~/Documents/OneClaw/ 下是否存在：ai-repair.command、repair.command、open-claude.command

第三步：用中文告诉用户
- 修复了哪些问题
- 现在 OpenClaw 的运行状态
- 接下来问用户：「还有什么需要帮助的吗？」'
    claude --dangerously-skip-permissions -p "$RESTORE_PROMPT" --output-format text 2>&1
    echo ""
fi

# Step 2: Enter interactive mode
echo ""
echo "  正在启动 Claude Code..."
echo "  用中文描述你的问题，例如："
echo "    「OpenClaw 报 AWS 签名错误，帮我修一下」"
echo "    「Chrome 连不上」"
echo "    「帮我看看日志哪里出错了」"
echo ""

cd ~/.openclaw/workspace 2>/dev/null || cd ~
claude
ASKCLAUDE_EOF
chmod +x "$HOME/Documents/OneClaw/open-claude.command"
success "Ask Claude script created: ~/Documents/OneClaw/open-claude.command"

# Create Chinese symlinks pointing to English-named .command files
ln -sf "repair.command" "$HOME/Documents/OneClaw/一键修复.command"
ln -sf "ai-repair.command" "$HOME/Documents/OneClaw/AI修复.command"
ln -sf "open-claude.command" "$HOME/Documents/OneClaw/打开Claude对话.command"
success "Chinese symlinks created (一键修复/AI修复/打开Claude对话 → English files)"

# ============================================================================
# Done!
# ============================================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║            安装完成！🎉                           ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}已安装的组件：${NC}"
echo "  ✅ fnm, Node.js, pnpm, uv, AWS CLI"
echo "  ✅ Claude Code（通过 Bedrock 调用 Claude 模型）"
echo "  ✅ OpenClaw（Gateway + Node + Guardian 守护进程）"
echo "  ✅ MCP 服务器（Chrome DevTools、AWS 文档）"
echo "  ✅ 开机自启动（LaunchAgents）"
echo "  ✅ 健康监控（每 60 秒自动检查）"
echo ""

echo -e "${BOLD}常用命令：${NC}"
echo "  claude                              — 启动 Claude Code（AI 编程助手）"
echo "  openclaw chat                       — 和 OpenClaw 对话"
echo "  openclaw status                     — 查看 OpenClaw 运行状态"
echo "  openclaw doctor                     — 诊断问题"
echo ""

echo -e "${BOLD}出问题了？打开访达 → 文稿 → OneClaw 文件夹，双击运行：${NC}"
echo -e "  📁 ~/Documents/OneClaw/${GREEN}repair.command${NC}       — 重启所有服务（中文别名：一键修复）"
echo -e "  📁 ~/Documents/OneClaw/${GREEN}ai-repair.command${NC}    — AI 自动诊断+修复（中文别名：AI修复）"
echo -e "  📁 ~/Documents/OneClaw/${GREEN}open-claude.command${NC}  — 用中文和 Claude 对话（中文别名：打开Claude对话）"
echo -e "  ${YELLOW}双击即可运行，无需其他操作${NC}"
echo ""

echo -e "${BOLD}控制面板：${NC}"
echo "  http://127.0.0.1:18789              — 在浏览器打开 OpenClaw 控制台"
echo ""
echo -e "${BOLD}Gateway Token（登录控制台时需要，请复制保存）：${NC}"
echo -e "  ${GREEN}${BOLD}${GATEWAY_TOKEN}${NC}"
echo ""


echo -e "${YELLOW}${BOLD}接下来做什么：${NC}"
echo -e "  1. 按 ${GREEN}Command + N${NC} 打开一个新的终端窗口（很重要！新窗口才能识别刚装的命令）"
echo -e "  2. 在新窗口输入：${CYAN}claude${NC}  然后按回车"
echo -e "  3. Claude Code 启动后，你可以用中文和它对话，让它帮你写代码、排查问题"
echo ""

if [ -n "$DISCORD_BOT_TOKEN" ]; then
    echo -e "  Discord 机器人已配置，OpenClaw 下次启动时会自动连接。"
fi

# Auth mode specific tips
case "$AWS_AUTH_MODE" in
    sso)
        echo -e "  ${YELLOW}${BOLD}SSO 提醒：${NC}SSO 凭证会过期（通常 8-12 小时），过期后运行："
        echo -e "  ${CYAN}aws sso login --profile ${AWS_PROFILE_NAME}${NC}"
        echo ""
        ;;
    profile)
        echo -e "  ${YELLOW}使用 AWS Profile: ${GREEN}${AWS_PROFILE_NAME}${NC}"
        echo ""
        ;;
esac

# Show configured channels summary
echo -e "${BOLD}已配置的消息平台：${NC}"
[ -n "$DISCORD_BOT_TOKEN" ] && echo "  ✅ Discord"
[ -n "$LARK_APP_ID" ] && echo "  ✅ 飞书/Lark"
[ -n "$TELEGRAM_BOT_TOKEN" ] && echo "  ✅ Telegram"
[ -n "$SLACK_BOT_TOKEN" ] && echo "  ✅ Slack"
[ -n "$WECOM_CORP_ID" ] && echo "  ✅ 企业微信 WeCom"
[ -n "$WECOM_WEBHOOK_URL" ] && echo "  ✅ 企业微信 Webhook"
[[ "${INSTALL_WECHAT:-N}" =~ ^[Yy] ]] && echo "  ✅ 个人微信（需扫码: openclaw connect wechat）"
[[ "${ENABLE_WHATSAPP:-N}" =~ ^[Yy] ]] && echo "  ✅ WhatsApp（需扫码: openclaw connect whatsapp）"
echo ""

# Auto-open OpenClaw control panel in browser (only if gateway is up)
if curl -s -o /dev/null -m 2 "http://127.0.0.1:18789/" 2>/dev/null; then
    info "正在打开 OpenClaw 控制面板..."
    open "http://127.0.0.1:18789"
else
    info "Gateway 尚未就绪，请稍后手动打开: http://127.0.0.1:18789"
fi

echo -e "${CYAN}${BOLD}遇到任何问题？${NC}"
echo ""
echo -e "  打开终端，输入 ${GREEN}${BOLD}claude${NC} 进入 AI 交互模式，直接用中文描述你的问题，比如："
echo -e "  ${CYAN}「OpenClaw 报 AWS 签名错误，帮我修一下」${NC}"
echo -e "  ${CYAN}「Chrome 连不上 OpenClaw」${NC}"
echo -e "  ${CYAN}「帮我检查 AWS 凭证是否正确」${NC}"
echo ""
echo -e "  或者打开访达 → 文稿 → OneClaw，双击脚本让 AI 全自动修复："
echo -e "  ${GREEN}~/Documents/OneClaw/ai-repair.command${NC}    — AI 自动诊断+修复（约 1-3 分钟）"
echo -e "  ${GREEN}~/Documents/OneClaw/repair.command${NC}      — 一键重启所有服务"
echo ""
echo -e "${GREEN}${BOLD}享受你的 AI 编程环境吧！${NC}"
