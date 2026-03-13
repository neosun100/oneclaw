#!/bin/bash
# ============================================================================
# All in One Claw — API Key Configuration Wizard
# ============================================================================
# Run after installation to configure API keys for MCP servers and services.
# Usage: bash configure-keys.sh
#
# This wizard lets you add/update API keys without re-running the full installer.
# Keys are written to ~/.mcp.json and environment configs.
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }

MCP_JSON="$HOME/.mcp.json"

echo -e "\n${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     All in One Claw — API Key Configuration      ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -f "$MCP_JSON" ]; then
    warn "~/.mcp.json not found. Please run the installer first."
    exit 1
fi

# Helper: update a key in .mcp.json env block
set_mcp_env() {
    local server="$1" key="$2" value="$3"
    python3 -c "
import json
with open('$MCP_JSON', 'r') as f:
    cfg = json.load(f)
servers = cfg.get('mcpServers', {})
if '$server' in servers:
    if 'env' not in servers['$server']:
        servers['$server']['env'] = {}
    servers['$server']['env']['$key'] = '$value'
    with open('$MCP_JSON', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('OK')
else:
    print('SERVER_NOT_FOUND')
" 2>/dev/null
}

# Helper: read current value
get_mcp_env() {
    local server="$1" key="$2"
    python3 -c "
import json
with open('$MCP_JSON', 'r') as f:
    cfg = json.load(f)
val = cfg.get('mcpServers', {}).get('$server', {}).get('env', {}).get('$key', '')
print(val)
" 2>/dev/null
}

show_status() {
    local server="$1" key="$2" label="$3"
    local val
    val=$(get_mcp_env "$server" "$key")
    if [ -n "$val" ] && [ "$val" != "" ]; then
        echo -e "  ${GREEN}●${NC} $label: ${GREEN}configured${NC}"
    else
        echo -e "  ${YELLOW}○${NC} $label: ${YELLOW}not set${NC}"
    fi
}

configure_key() {
    local server="$1" key="$2" label="$3" url="$4"
    local current
    current=$(get_mcp_env "$server" "$key")
    if [ -n "$current" ] && [ "$current" != "" ]; then
        echo -e "  当前已配置: ${GREEN}${current:0:8}...${NC}"
        echo -en "  ${YELLOW}重新输入（按回车保留当前值）: ${NC}"
    else
        echo -e "  获取方式: ${CYAN}$url${NC}"
        echo -en "  ${YELLOW}请输入 $label: ${NC}"
    fi
    read -r value
    if [ -n "$value" ]; then
        set_mcp_env "$server" "$key" "$value"
        success "$label 已更新"
    else
        info "保留当前值"
    fi
}

echo -e "${BOLD}当前 API Key 状态：${NC}\n"
show_status "github" "GITHUB_PERSONAL_ACCESS_TOKEN" "GitHub Token"
show_status "brave-search" "BRAVE_API_KEY" "Brave Search API Key"
show_status "tavily" "TAVILY_API_KEY" "Tavily API Key"

echo ""
echo -e "${BOLD}配置 API Keys（按回车跳过不需要的）：${NC}\n"

echo -e "${CYAN}1. GitHub Personal Access Token${NC}"
echo -e "   用途: GitHub MCP — 管理 PR、Issue、代码搜索"
configure_key "github" "GITHUB_PERSONAL_ACCESS_TOKEN" "GitHub Token" "https://github.com/settings/tokens → Generate new token (classic)"

echo ""
echo -e "${CYAN}2. Brave Search API Key${NC}"
echo -e "   用途: Brave Search MCP — 网页搜索"
configure_key "brave-search" "BRAVE_API_KEY" "Brave API Key" "https://brave.com/search/api/ → Get API Key"

echo ""
echo -e "${CYAN}3. Tavily API Key${NC}"
echo -e "   用途: Tavily MCP — AI 优化的网页搜索"
configure_key "tavily" "TAVILY_API_KEY" "Tavily API Key" "https://tavily.com → Sign up → API Key"

echo ""
echo -e "${BOLD}最终状态：${NC}\n"
show_status "github" "GITHUB_PERSONAL_ACCESS_TOKEN" "GitHub Token"
show_status "brave-search" "BRAVE_API_KEY" "Brave Search API Key"
show_status "tavily" "TAVILY_API_KEY" "Tavily API Key"

echo ""
echo -e "${GREEN}${BOLD}配置完成！${NC}"
echo -e "  重启 Claude Code 后生效: 退出 claude 再重新打开"
echo -e "  或运行: ${CYAN}claude /mcp${NC} 查看 MCP 状态"
echo ""
