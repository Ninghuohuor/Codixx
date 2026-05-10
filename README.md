# Codixx

Codixx is a native macOS menu bar app for people who use Codex heavily and want a local way to track usage, monitor quota state, and switch between saved Codex accounts.

The app is local-first. It reads Codex data from files on your Mac, stores account snapshots and API keys in macOS Keychain, and does not upload your authentication data, API keys, token logs, or account data to any remote server.

## Features

- **Menu bar dashboard**: Open a compact macOS popover from the menu bar to view Codex usage and account state.
- **Quota monitoring**: Track the current account's 5-hour quota and weekly quota from local Codex session data.
- **Token usage overview**: View total usage, recent trends, active thread usage, and top token-consuming threads.
- **Multiple account snapshots**: Save local Codex account auth snapshots with readable aliases.
- **Manual account switching**: Switch the local Codex auth state between saved accounts.
- **Automatic switching**: Switch to another available account when configured quota thresholds are reached.
- **API provider accounts**: Save API-provider credentials, switch Codex into API-key mode, and preserve existing local Codex history.
- **Switch audit log**: Keep local switch records without storing raw tokens or full auth JSON in the log.
- **Packaging script**: Build a standalone `Codixx.app` bundle for local use.

## Privacy and Security

Codixx is designed for local personal use.

- Codixx reads from local Codex files such as `~/.codex/auth.json`, `~/.codex/state_*.sqlite`, and Codex session JSONL files.
- Saved ChatGPT/Codex auth snapshots are stored in macOS Keychain.
- Saved API keys are stored in macOS Keychain.
- Local metadata is stored under `~/Library/Application Support/Codixx`.
- Switch backups are stored locally under `~/Library/Application Support/Codixx/backups`.
- Audit logs record switch summaries, aliases, timestamps, and backup paths, not raw auth data.
- Codixx does not provide cloud sync, team management, or remote telemetry.

Always make sure you can recover your Codex login before testing account switching.

## Data Sources

Codixx reads local Codex data from the current macOS user profile.

Common local sources include:

```text
~/.codex/auth.json
~/.codex/config.toml
~/.codex/state_*.sqlite
~/.codex/sessions/**/*.jsonl
~/.codex/archived_sessions/*.jsonl
~/Library/Application Support/Codex
```

Codixx also maintains its own local app data:

```text
~/Library/Application Support/Codixx/config.json
~/Library/Application Support/Codixx/accounts.json
~/Library/Application Support/Codixx/backups
~/Library/Application Support/Codixx/logs
~/Library/Application Support/Codixx/switch_audit.jsonl
```

## Requirements

- macOS 13 Ventura or newer
- Swift 5.9 or newer
- Xcode command line tools
- A local Codex installation/profile if you want to read real usage and switch accounts

## Build and Test

Run the test suite:

```bash
swift test
```

Build a release binary:

```bash
swift build -c release
```

Package a local `.app` bundle:

```bash
./scripts/package_app.sh
```

The packaged app is created at:

```text
build/Codixx.app
```

The packaging script builds the release executable, creates the macOS app bundle, writes `Info.plist`, copies the app icon, and signs the app with the local signing identity when available.

## Manual Verification

See the manual checklist:

```text
docs/manual-test-checklist.md
```

Important checks include:

- Launch without `~/.codex` and confirm the app shows a recoverable empty/degraded state.
- Launch with a real Codex profile and confirm usage can be read.
- Save an account and verify raw auth data is not written to `accounts.json`.
- Switch between two saved accounts and verify a backup is created.
- Add an API provider account and confirm raw API keys are not written to metadata.
- Run the packaging script and confirm `build/Codixx.app` launches as a menu bar app.

## Repository Layout

```text
Sources/CodixxApp        macOS app entry point, app state, UI, lifecycle, notifications
Sources/CodixxCore       account models, persistence, switching, usage readers, support utilities
Tests                    unit and integration-style tests for app and core behavior
Resources                app icon resources
fixtures                 small synthetic test fixtures
docs                     manual checks, implementation plans, and design notes
scripts                  packaging scripts
```

## License

No license has been published yet. Until a license is added, all rights are reserved by default.

---

# Codixx 中文说明

Codixx 是一个原生 macOS 菜单栏 App，面向长期使用 Codex、需要关注 token 消耗、额度状态和本地账号切换的个人用户。

它的核心目标是：在本机读取 Codex 的本地数据，在菜单栏中展示使用情况，并在需要时安全地切换本地保存的 Codex 账号。Codixx 优先服务本地自用场景，不依赖云端后台。

## 主要功能

- **菜单栏面板**：从 macOS 顶部菜单栏打开 Codixx 面板，查看当前账号、额度和使用情况。
- **额度监控**：从本地 Codex 会话数据读取 5 小时额度和周额度状态。
- **Token 用量概览**：展示总 token、近期趋势、当前活跃线程和 token 消耗最高的线程。
- **多账号保存**：把本地 Codex 登录快照保存为多个账号，并为每个账号设置别名。
- **手动切换账号**：在 Codixx 中手动切换本地 Codex auth 状态。
- **自动切换账号**：当当前账号额度达到设定阈值时，自动切换到其他可用账号。
- **API Provider 账号**：支持保存 API provider 的 base URL、API key 和默认模型，并切换到 API key 模式。
- **切换审计日志**：记录切换摘要、时间、别名和备份路径，不记录原始 token 或完整 auth JSON。
- **本地打包脚本**：通过脚本生成可直接运行的 `Codixx.app`。

## 隐私与安全

Codixx 是本地优先工具。

- Codixx 会读取 `~/.codex/auth.json`、`~/.codex/state_*.sqlite`、Codex session JSONL 等本地文件。
- ChatGPT/Codex 登录快照保存在 macOS Keychain。
- API key 保存在 macOS Keychain。
- 应用自身配置和非敏感账号元数据保存在 `~/Library/Application Support/Codixx`。
- 切换前的备份保存在 `~/Library/Application Support/Codixx/backups`。
- 审计日志只记录切换摘要，不保存原始认证数据。
- Codixx 不上传认证信息、API key、token 日志或账号数据到远程服务器。
- Codixx 不提供云同步、团队后台或远程遥测。

测试账号切换前，请确保你能恢复自己的 Codex 登录状态。

## 本地数据来源

Codixx 读取当前 macOS 用户目录下的 Codex 本地数据。

常见读取路径：

```text
~/.codex/auth.json
~/.codex/config.toml
~/.codex/state_*.sqlite
~/.codex/sessions/**/*.jsonl
~/.codex/archived_sessions/*.jsonl
~/Library/Application Support/Codex
```

Codixx 自己维护的本地数据：

```text
~/Library/Application Support/Codixx/config.json
~/Library/Application Support/Codixx/accounts.json
~/Library/Application Support/Codixx/backups
~/Library/Application Support/Codixx/logs
~/Library/Application Support/Codixx/switch_audit.jsonl
```

## 运行要求

- macOS 13 Ventura 或更高版本
- Swift 5.9 或更高版本
- Xcode Command Line Tools
- 如果要读取真实用量和切换账号，需要本机已经安装并登录过 Codex

## 构建与测试

运行测试：

```bash
swift test
```

构建 release 版本：

```bash
swift build -c release
```

打包本地 `.app`：

```bash
./scripts/package_app.sh
```

打包后的 App 位于：

```text
build/Codixx.app
```

打包脚本会构建 release 可执行文件，创建 macOS app bundle，写入 `Info.plist`，复制应用图标，并在本机存在签名身份时进行本地签名。

## 手动验证

手动测试清单见：

```text
docs/manual-test-checklist.md
```

重点建议验证：

- 没有 `~/.codex` 时启动，App 能显示可恢复的空状态或降级状态。
- 存在真实 Codex profile 时启动，能读取本地用量。
- 保存账号后，确认 `accounts.json` 不包含原始 auth JSON。
- 在两个已保存账号之间切换，确认会创建备份。
- 添加 API provider 账号后，确认 API key 不会写入元数据文件。
- 运行打包脚本，确认 `build/Codixx.app` 能以菜单栏 App 形式启动。

## 仓库结构

```text
Sources/CodixxApp        macOS App 入口、状态、UI、生命周期和通知
Sources/CodixxCore       账号模型、持久化、切换逻辑、用量读取和基础工具
Tests                    App 与 Core 的测试
Resources                App 图标资源
fixtures                 小型合成测试数据
docs                     手动测试清单、实现计划和设计说明
scripts                  打包脚本
```

## 许可证

当前项目暂未发布开源许可证。在添加许可证之前，默认保留所有权利。
