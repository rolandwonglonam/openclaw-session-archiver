# OpenClaw Session Archiver

## 问题描述

OpenClaw/Clawdbot 在长时间运行后，session 文件会积累大量消息（几百条甚至上千条），导致：
- ❌ API 响应极慢（几分钟甚至超时）
- ❌ Discord bot 返回 502 错误
- ❌ 内存占用过高
- ❌ 用户体验极差

## 解决方案

本工具提供**自动归档系统**，实现：
- ✅ 自动清理超过指定数量的旧消息
- ✅ 保留完整对话历史到归档文件
- ✅ 保持 API 快速响应
- ✅ 文件锁机制防止并发冲突
- ✅ 自动同步到机器人记忆系统

## 工作原理

```
┌─────────────────────────────────────┐
│  活跃 Session (最近 N 条消息)        │
│  → 快速 API 响应                     │
└──────────┬──────────────────────────┘
           │ 超过阈值时自动归档
           ↓
┌─────────────────────────────────────┐
│  归档文件 (所有历史消息)             │
│  → 完整记录保留                      │
└─────────────────────────────────────┘
```

## 快速安装

### 方法 1：一键安装（推荐）

```bash
# 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/openclaw-session-archiver/main/install.sh | bash
```

### 方法 2：手动安装

```bash
# 1. 下载脚本
git clone https://github.com/YOUR_REPO/openclaw-session-archiver.git
cd openclaw-session-archiver

# 2. 运行安装
sudo bash install.sh
```

## 配置说明

安装后会创建配置文件：`/etc/openclaw-archiver.conf`

```bash
# OpenClaw Session 归档配置

# Session 文件目录（根据你的安装路径修改）
SESSIONS_DIR="/volume1/docker/openclaw/config/agents/main/sessions"

# 归档文件存储目录
MEMORY_DIR="/volume1/docker/openclaw/config/memory"

# 保留的最大消息数（超过此数量将被归档）
MAX_MESSAGES=50

# 机器人工作区目录（用于同步记忆）
WORKSPACE_DIR="/volume1/docker/openclaw/workspace"

# 定时任务频率（cron 格式）
# 默认：每小时运行一次
CRON_SCHEDULE="0 * * * *"
```

## 使用说明

### 查看状态

```bash
# 查看归档日志
tail -f /var/log/openclaw-archive.log

# 查看归档文件
ls -lh /volume1/docker/openclaw/config/memory/
```

### 手动运行

```bash
# 立即执行一次归档
sudo /usr/local/bin/openclaw-archive-sessions.sh
```

### 修改配置

```bash
# 编辑配置文件
sudo nano /etc/openclaw-archiver.conf

# 重新加载配置（重启 cron）
sudo systemctl restart cron  # Linux
# 或
sudo launchctl unload /Library/LaunchDaemons/com.openclaw.archiver.plist
sudo launchctl load /Library/LaunchDaemons/com.openclaw.archiver.plist  # macOS
```

## 卸载

```bash
sudo bash /usr/local/bin/openclaw-archiver-uninstall.sh
```

## 常见问题

### Q: 归档后机器人会忘记之前的对话吗？

A: 不会。所有消息都被保存到归档文件中，并自动同步到 `MEMORY.md`，机器人可以访问这些历史记录。

### Q: 多久运行一次归档？

A: 默认每小时一次。你可以在配置文件中修改 `CRON_SCHEDULE`。

### Q: 会影响正在进行的对话吗？

A: 不会。脚本使用文件锁机制，确保不会在 OpenClaw 写入时进行归档。

### Q: 如何恢复归档的消息？

A: 归档文件保存在 `MEMORY_DIR` 目录中，每个 session 都有独立的归档文件 `{session_id}_memory.md`。

### Q: 支持哪些系统？

A:
- ✅ Linux (Ubuntu, Debian, CentOS, etc.)
- ✅ Synology NAS (DSM 7.x)
- ✅ macOS
- ✅ Docker 环境

## 技术细节

### 文件锁机制

使用 `flock` 确保：
- 同一时间只有一个归档进程运行
- 不会与 OpenClaw 的文件写入冲突
- 10 秒超时避免死锁

### 归档策略

1. 检测 session 文件行数
2. 如果超过 `MAX_MESSAGES`：
   - 提取超出部分的消息
   - 追加到 session 专属归档文件
   - 同时追加到全局归档文件
   - 截断 session 文件保留最近消息
3. 同步最新归档到 `MEMORY.md`

### 性能影响

- CPU: 极低（每小时运行几秒）
- 内存: < 10MB
- 磁盘 I/O: 最小化（仅处理超过阈值的文件）

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 作者

Created by the OpenClaw Community

## 更新日志

### v1.0.0 (2026-02-01)
- 初始版本
- 支持自动归档
- 文件锁机制
- 全局记忆同步
