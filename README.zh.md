# OneClaw

一键安装 Claude Code + OpenClaw + AWS 全家桶 — 支持 Mac、Linux 和 Docker。

**完全不懂技术的小白也能用** — 打开终端，粘贴一行命令，按提示输入 AWS 密钥即可。

[English](README.md)

## 使用方法

### macOS (Apple Silicon)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/setup.sh)"
```

### Linux (Ubuntu/Debian/RHEL/Fedora)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/install-linux.sh)"
```

### Docker

```bash
git clone --depth 1 https://github.com/cncoder/oneclaw.git && cd oneclaw
docker compose up -d
```

## 系统要求

| 平台 | 要求 |
|------|------|
| **macOS** | macOS 13+, Apple Silicon (M1-M4), 推荐 16 GB 内存 |
| **Linux** | Ubuntu 22.04+ / Debian 12+ / Fedora 38+ / RHEL 9+, 最低 4 GB 内存 |
| **Docker** | Docker 24+, Docker Compose v2, 4 GB 内存 |

## AWS 认证方式

安装器支持 **4 种认证方式**，选择适合你的：

| 方式 | 适用场景 | 凭证有效期 |
|------|----------|-----------|
| **1. Access Key + Secret Key** | 个人用户，快速上手 | 永久（直到轮换） |
| **2. AWS SSO / IAM Identity Center** | 企业团队 | 8-12 小时（自动刷新） |
| **3. 使用已有 AWS Profile** | 已配置过 `aws configure` | 取决于 profile 类型 |
| **4. 跳过** | 已有 `~/.aws/` 凭证 | N/A |

### 方式 1: 静态密钥（最简单）

从 AWS Console → IAM → Users → Security credentials → Create access key 获取

### 方式 2: AWS SSO（企业推荐）

需要管理员提供：
- SSO Start URL（如 `https://my-org.awsapps.com/start`）
- SSO Region、Account ID、Role Name

安装器会自动打开浏览器完成 SSO 登录，凭证通过 `CLAUDE_CODE_AWS_AUTH_REFRESH` 自动刷新。

```bash
# SSO 会话过期时（每 8-12 小时）：
aws sso login --profile bedrock-sso
```

### 方式 3: 已有 Profile

如果已经运行过 `aws configure`，直接告诉安装器使用哪个 profile。

### IAM 权限要求

AWS IAM 用户需要以下权限才能正常使用：

**最简方式**：附加 AWS 托管策略 `AmazonBedrockFullAccess`

**最小权限策略**（推荐生产环境使用）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/*"
    }
  ]
}
```

> **还需要在 Bedrock 控制台开启模型访问**：AWS Console → Bedrock → Model access → 勾选 Anthropic Claude 全系列 → Save changes

## 自动安装的组件

- **fnm** — Fast Node Manager（管理 Node.js 版本）
- **Node.js** — JavaScript 运行时（通过 fnm 安装）
- **pnpm** — 快速包管理器
- **uv / uvx** — Python 包管理（MCP 服务器需要）
- **AWS CLI** — AWS 命令行工具
- **Claude Code** — AI 编程助手（通过 Bedrock）
- **OpenClaw** — AI Agent 框架（Gateway + Node）
- **MCP 服务器** — Chrome DevTools、AWS 文档
- **Guardian 守护进程** — 每 60 秒健康检查 + 自动修复
- **LaunchAgent** — 开机自启动

## 安装后可用命令

```bash
claude                              # 启动 Claude Code
openclaw chat                       # 和 OpenClaw 对话
openclaw status                     # 查看 OpenClaw 状态
openclaw doctor                     # 诊断问题
```

## Web 控制台

安装完成后访问 http://127.0.0.1:18789 打开 OpenClaw 控制面板。

## 手动安装（一键脚本失败时）

如果脚本在某一步失败了，可以手动安装对应组件后重新运行脚本——已安装的会自动跳过。

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. fnm + Node.js
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.zshrc
fnm install --lts

# 3. pnpm
corepack enable && corepack prepare pnpm@latest --activate
# 或者: npm install -g pnpm

# 4. uv（Python 包管理器）
curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. AWS CLI（官方安装包）
curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /

# 6. Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# 7. OpenClaw
curl -fsSL https://openclaw.ai/install.sh | bash
```

手动装完后，重新运行脚本完成配置：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/setup.sh)"
```

## 出了问题怎么办

打开**访达 → 文稿 → OneClaw** 文件夹，双击对应文件即可：

### 方案 1: 一键修复

双击 **`一键修复.command`** — 停止→清理→重启所有服务（解决 99% 的问题）

### 方案 2: AI 智能修复（推荐）

双击 **`AI修复.command`** — Claude 全自动排查+修复，约 1-3 分钟

Claude Code 会自动执行：
- 检查 `openclaw status` 和 `openclaw doctor`
- 读取 gateway/node/chrome 的错误日志
- 检查 LaunchAgent 和端口状态
- 验证 AWS 凭证
- **自动修复发现的问题**
- 重启所有服务并验证

### 方案 3: 和 Claude 对话

双击 **`打开Claude对话.command`** — 用中文描述问题，Claude 帮你解决

### 方案 4: 老用户升级

如果你用的是早期版本，运行一次即可获得最新快捷方式：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/fix.sh)"
```

### 方案 5: 查看日志

```bash
# macOS
tail -50 ~/.openclaw/logs/gateway.log      # Gateway 日志
tail -50 ~/.openclaw/logs/gateway.err.log  # Gateway 错误日志
tail -50 ~/.openclaw/logs/guardian.log     # 守护进程日志

# Linux (systemd)
journalctl --user -u openclaw-gateway -f   # Gateway 日志（实时）
journalctl --user -u openclaw-node -f      # Node 日志（实时）
systemctl --user status openclaw-gateway   # 服务状态
```

### 方案 6: 重新安装

再跑一次 setup.sh 即可，已安装的组件会自动跳过。

## OpenClaw Skills（推荐安装）

本仓库 `skills/` 目录包含四个预置 Skill，安装后可以显著提升 OpenClaw + Claude Code 的能力：

| Skill | 说明 |
|-------|------|
| `claude-code` | 教 OpenClaw 如何高效调度 Claude Code：任务拆分、渐进式交付、Slot Machine 恢复、终端交互、调试流程 |
| `aws-infra` | 通过 AWS CLI 进行基础设施查询、审计、监控，默认只读，写操作需确认 |
| `chrome-devtools` | 通过 Chrome DevTools Protocol (CDP) 控制浏览器：UI 验证、网页抓取、截图调试、前端测试 |
| `skill-vetting` | 从 ClawHub 安装第三方 Skill 前的安全审查工具，含自动扫描器和 prompt injection 防护 |

### 安装方法

在终端打开 Claude Code，让它帮你安装：

```bash
claude
```

然后输入：

```
把 https://github.com/cncoder/oneclaw 仓库里 skills/ 目录下的四个 skill
（claude-code、aws-infra、chrome-devtools、skill-vetting）安装到 OpenClaw。
把每个 skill 的目录复制到 ~/.openclaw/workspace/skills/ 下即可。
```

或者手动复制：

```bash
git clone --depth 1 https://github.com/cncoder/oneclaw.git /tmp/oneclaw
cp -r /tmp/oneclaw/skills/claude-code ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/aws-infra ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/chrome-devtools ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/skill-vetting ~/.openclaw/workspace/skills/
rm -rf /tmp/oneclaw
```

## 卸载

完全移除 OneClaw 及所有组件：

```bash
# 1. 停止并移除 LaunchAgent
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.*.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/ai.openclaw.*.plist

# 2. 移除 OpenClaw
openclaw uninstall 2>/dev/null   # 如果你的版本支持此命令
rm -rf ~/.openclaw

# 3. 移除快捷方式
rm -rf ~/Documents/OneClaw

# 4.（可选）移除 Claude Code
npm uninstall -g @anthropic-ai/claude-code 2>/dev/null

# 5.（可选）移除 MCP 配置
# 检查并编辑 ~/.mcp.json — 删除 OneClaw 添加的条目
```

> fnm、Node.js、AWS CLI、uv 是通用工具 — 只有确认没有其他项目依赖时才卸载。

## 安全说明

- AWS 密钥只存在本地 `~/.aws/credentials`，不会上传
- Gateway Token 自动生成，绑定 loopback（只能本机访问）
- 不包含任何硬编码密钥
- 所有服务只监听 127.0.0.1

## 文件结构

### macOS

```
~/Documents/OneClaw/
├── 一键修复.command             一键修复（双击运行）
├── AI修复.command               AI 智能修复（双击运行）
└── 打开Claude对话.command       打开 Claude 对话（双击运行）
~/.aws/                         AWS 凭证
~/.claude/settings.json         Claude Code 配置
~/.mcp.json                     MCP 服务器配置
~/.openclaw/
├── openclaw.json               OpenClaw 主配置
├── chrome-profile/             Chrome CDP 专用数据目录
├── logs/                       所有日志
├── scripts/
│   ├── guardian-check.sh       守护进程脚本
│   ├── repair.sh              紧急修复脚本
│   └── ai-repair.sh           AI 智能修复脚本
└── workspace/                  OpenClaw 工作区
    └── CLAUDE.md              工作区说明
~/Library/LaunchAgents/
├── ai.openclaw.chrome.plist    Chrome CDP 自启动（端口 9222）
├── ai.openclaw.gateway.plist   Gateway 自启动
├── ai.openclaw.node.plist      Node 自启动
└── ai.openclaw.guardian.plist  守护进程自启动
```

### Linux

```
~/.aws/                                     AWS 凭证
~/.claude/settings.json                     Claude Code 配置
~/.mcp.json                                 MCP 服务器配置
~/.openclaw/
├── openclaw.json                           OpenClaw 主配置
├── chrome-profile/                         Chromium CDP 数据
├── logs/                                   所有日志
├── scripts/guardian-check.sh               守护进程脚本
└── workspace/                              OpenClaw 工作区
~/.config/systemd/user/
├── openclaw-chrome.service                 Chromium CDP 服务
├── openclaw-gateway.service                Gateway 服务
├── openclaw-node.service                   Node 服务
├── openclaw-guardian.service               Guardian oneshot
└── openclaw-guardian.timer                 Guardian 60 秒定时器
```

## 测试

```bash
# 运行完整测试套件（254 个测试用例）
bash tests/run_tests.sh
```

55 个测试类别，覆盖单元测试、功能测试、E2E 测试、集成测试和回归测试。详见 [tests/TESTING.md](tests/TESTING.md)。

## 许可证

MIT
