# OneClaw

One-click setup for **Claude Code + OpenClaw + AWS** — Mac, Linux, and Docker.

Zero technical knowledge required — open Terminal, paste one command, enter your AWS keys, done.

[中文文档](README.zh.md)

## Quick Start

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

## System Requirements

| Platform | Requirements |
|----------|-------------|
| **macOS** | macOS 13+, Apple Silicon (M1-M4), 16 GB RAM recommended |
| **Linux** | Ubuntu 22.04+ / Debian 12+ / Fedora 38+ / RHEL 9+, 4 GB RAM minimum |
| **Docker** | Docker 24+, Docker Compose v2, 4 GB RAM |

## AWS Authentication Methods

The installer supports **4 authentication methods** — choose what fits your setup:

| Method | Best For | Credential Lifetime |
|--------|----------|-------------------|
| **1. Access Key + Secret Key** | Personal use, quick setup | Permanent (until rotated) |
| **2. AWS SSO / IAM Identity Center** | Enterprise, teams | 8-12 hours (auto-refresh) |
| **3. Existing AWS Profile** | Already configured `aws configure` | Depends on profile type |
| **4. Skip** | Credentials already in `~/.aws/` | N/A |

### Method 1: Static Keys (simplest)

Get an Access Key from: AWS Console → IAM → Users → Security credentials → Create access key

### Method 2: AWS SSO (recommended for enterprise)

You'll need from your admin:
- SSO Start URL (e.g., `https://my-org.awsapps.com/start`)
- SSO Region, Account ID, Role Name

The installer will open your browser for SSO login. Credentials auto-refresh via `CLAUDE_CODE_AWS_AUTH_REFRESH`.

```bash
# When SSO session expires (every 8-12h):
aws sso login --profile bedrock-sso
```

### Method 3: Existing Profile

If you've already run `aws configure`, just tell the installer which profile to use.

### IAM Permissions Required

**Easiest**: Attach `AmazonBedrockFullAccess`

**Least-privilege** (recommended):

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

> **Enable model access**: AWS Console → Bedrock → Model access → Select all Anthropic Claude models → Save

## What Gets Installed

- **fnm** — Fast Node Manager (manages Node.js versions)
- **Node.js** — JavaScript runtime (installed via fnm)
- **pnpm** — Fast package manager
- **uv / uvx** — Python package manager (for MCP servers)
- **AWS CLI** — AWS command-line tools
- **Claude Code** — AI coding assistant (via Bedrock)
- **OpenClaw** — AI Agent framework (Gateway + Node)
- **MCP Servers** — Chrome DevTools, AWS Documentation
- **Guardian Daemon** — Health check every 60s + auto-repair
- **LaunchAgents** — Auto-start on boot

## Usage

```bash
claude                              # Launch Claude Code
openclaw chat                       # Chat with OpenClaw
openclaw status                     # Check OpenClaw status
openclaw doctor                     # Diagnose issues
```

## Web Dashboard

After installation, open http://127.0.0.1:18789 in your browser for the OpenClaw control panel.

## Manual Install (if one-click fails)

If the script fails at a specific step, you can install the prerequisites manually and re-run the script — it will skip anything already installed.

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. fnm + Node.js
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.zshrc
fnm install --lts

# 3. pnpm
corepack enable && corepack prepare pnpm@latest --activate
# or: npm install -g pnpm

# 4. uv (Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. AWS CLI (official installer)
curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /

# 6. Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# 7. OpenClaw
curl -fsSL https://openclaw.ai/install.sh | bash
```

After installing the prerequisites, re-run the setup script to configure everything:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/setup.sh)"
```

## Troubleshooting

### Option 1: One-Click Repair

Open **Finder → Documents → OneClaw** and double-click:

- **`一键修复.command`** — Stop → clean → restart all services (fixes 99% of issues)

### Option 2: AI-Powered Repair (Recommended)

Open **Finder → Documents → OneClaw** and double-click:

- **`AI修复.command`** — Claude auto-diagnoses + fixes (~1-3 min)

Claude Code will automatically:
- Run `openclaw status` and `openclaw doctor`
- Read gateway/node/chrome error logs
- Check LaunchAgent and port status
- Verify AWS credentials
- **Auto-fix any issues found**
- Restart all services and verify

### Option 3: Chat with Claude

Open **Finder → Documents → OneClaw** and double-click:

- **`打开Claude对话.command`** — Describe your problem in Chinese, Claude will help

### Option 4: Upgrade (existing users)

If you installed an older version, run this once to get the latest shortcuts:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cncoder/oneclaw/main/fix.sh)"
```

### Option 5: Check Logs

```bash
# macOS
tail -50 ~/.openclaw/logs/gateway.log      # Gateway log
tail -50 ~/.openclaw/logs/gateway.err.log  # Gateway error log
tail -50 ~/.openclaw/logs/guardian.log     # Guardian daemon log

# Linux (systemd)
journalctl --user -u openclaw-gateway -f   # Gateway log (live)
journalctl --user -u openclaw-node -f      # Node log (live)
systemctl --user status openclaw-gateway   # Service status
```

### Option 6: Reinstall

Just run `setup.sh` again — already-installed components will be skipped.

## OpenClaw Skills (Recommended)

The `skills/` directory in this repo contains four pre-built Skills that significantly enhance OpenClaw + Claude Code:

| Skill | Description |
|-------|-------------|
| `claude-code` | Teaches OpenClaw how to effectively dispatch Claude Code: task splitting, progressive delivery, Slot Machine recovery, terminal interaction, debugging workflow |
| `aws-infra` | AWS infrastructure queries, auditing, and monitoring via AWS CLI — read-only by default, write actions require confirmation |
| `chrome-devtools` | Browser automation via Chrome DevTools Protocol (CDP): UI verification, web scraping, screenshot-based debugging, frontend testing |
| `skill-vetting` | Security review tool for vetting third-party Skills from ClawHub before installation, with automated scanner and prompt injection defense |
| `architecture-svg` | Generate professional dark-theme SVG architecture diagrams for GitHub README — renders natively, no image hosting needed |

### Installation

Open Claude Code in your terminal and ask it to install:

```bash
claude
```

Then type:

```
Install the four skills (claude-code, aws-infra, chrome-devtools, skill-vetting) from
https://github.com/cncoder/oneclaw into OpenClaw.
Copy each skill directory to ~/.openclaw/workspace/skills/.
```

Or install manually:

```bash
git clone --depth 1 https://github.com/cncoder/oneclaw.git /tmp/oneclaw
cp -r /tmp/oneclaw/skills/claude-code ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/aws-infra ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/chrome-devtools ~/.openclaw/workspace/skills/
cp -r /tmp/oneclaw/skills/skill-vetting ~/.openclaw/workspace/skills/
rm -rf /tmp/oneclaw
```

## Uninstall

To completely remove OneClaw and all its components:

```bash
# 1. Stop and remove LaunchAgents
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.*.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/ai.openclaw.*.plist

# 2. Remove OpenClaw
openclaw uninstall 2>/dev/null   # if supported by your version
rm -rf ~/.openclaw

# 3. Remove OneClaw shortcuts
rm -rf ~/Documents/OneClaw

# 4. (Optional) Remove Claude Code
npm uninstall -g @anthropic-ai/claude-code 2>/dev/null

# 5. (Optional) Remove MCP config added by setup
# Review and edit ~/.mcp.json — remove the entries added by OneClaw
```

> fnm, Node.js, AWS CLI, and uv are shared tools — only remove them if no other project depends on them.

## Security

- AWS credentials stay local in `~/.aws/credentials`, never uploaded
- Gateway token is auto-generated, bound to loopback (localhost only)
- No hardcoded secrets in the script
- All services listen on 127.0.0.1 only

## File Layout

### macOS

```
~/Documents/OneClaw/
├── 一键修复.command             One-click repair (double-click to run)
├── AI修复.command               AI-powered repair (double-click to run)
└── 打开Claude对话.command       Open Claude Code chat (double-click to run)
~/.aws/                         AWS credentials
~/.claude/settings.json         Claude Code config
~/.mcp.json                     MCP server config
~/.openclaw/
├── openclaw.json               OpenClaw main config
├── chrome-profile/             Chrome CDP data directory
├── logs/                       All logs
├── scripts/
│   ├── guardian-check.sh       Guardian daemon script
│   ├── repair.sh              Emergency repair script
│   └── ai-repair.sh           AI-powered repair script
└── workspace/                  OpenClaw workspace
    └── CLAUDE.md              Workspace instructions
~/Library/LaunchAgents/
├── ai.openclaw.chrome.plist    Chrome CDP auto-start (port 9222)
├── ai.openclaw.gateway.plist   Gateway auto-start
├── ai.openclaw.node.plist      Node auto-start
└── ai.openclaw.guardian.plist  Guardian daemon auto-start
```

### Linux

```
~/.aws/                                     AWS credentials
~/.claude/settings.json                     Claude Code config
~/.mcp.json                                 MCP server config
~/.openclaw/
├── openclaw.json                           OpenClaw main config
├── chrome-profile/                         Chromium CDP data
├── logs/                                   All logs
├── scripts/guardian-check.sh               Guardian script
└── workspace/                              OpenClaw workspace
~/.config/systemd/user/
├── openclaw-chrome.service                 Chromium CDP service
├── openclaw-gateway.service                Gateway service
├── openclaw-node.service                   Node service
├── openclaw-guardian.service               Guardian oneshot
└── openclaw-guardian.timer                 Guardian 60s timer
```

## Testing

```bash
# Run the full test suite (306 test cases)
bash tests/run_tests.sh
```

61 test categories covering unit tests, functional tests, E2E tests, integration tests, and regression tests. See [tests/TESTING.md](tests/TESTING.md) for full documentation.

## License

MIT
