# OpenClaw Session Archiver

> **🎉 v2.0 重大更新：AI 智能压缩，告别"失忆"问题！**

## 问题描述

OpenClaw/Clawdbot 在长时间运行后，session 文件会积累大量消息（几百条甚至上千条），导致：
- ❌ API 响应极慢（几分钟甚至超时）
- ❌ Discord bot 返回 502 错误
- ❌ 内存占用过高
- ❌ 用户体验极差
- ❌ **简单截断导致机器人"失忆"，丢失重要上下文**

## 解决方案

本工具提供**智能压缩归档系统**，实现：
- ✅ **AI 驱动的智能压缩**（v2.0 新特性）
- ✅ **保持上下文连贯性**，机器人不会"失忆"
- ✅ 自动清理超过指定数量的旧消息
- ✅ 保留完整对话历史到归档文件
- ✅ 保持 API 快速响应
- ✅ 文件锁机制防止并发冲突
- ✅ 自动同步到机器人记忆系统

## 工作原理

### v2.0 智能压缩模式

```
┌─────────────────────────────────────┐
│  活跃 Session (120+ 条消息)         │
└──────────┬──────────────────────────┘
           │ 触发智能压缩
           ↓
┌─────────────────────────────────────┐
│  AI 分析前 80 条消息                 │
│  → 生成结构化摘要                    │
│  → 保留关键信息、决定、偏好          │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  压缩后 Session (41 条)              │
│  ├─ 1 条 AI 摘要                     │
│  └─ 40 条最近完整消息                │
│  → 快速 API 响应 + 上下文连贯        │
└──────────┬──────────────────────────┘
           │ 原始消息归档
           ↓
┌─────────────────────────────────────┐
│  归档文件 (所有历史消息)             │
│  → 完整记录保留                      │
└─────────────────────────────────────┘
```

### v1.0 简单截断模式（已弃用）

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
curl -fsSL https://raw.githubusercontent.com/rolandwonglonam/openclaw-session-archiver/main/install.sh | bash
```

### 方法 2：手动安装

```bash
# 1. 下载脚本
git clone https://github.com/rolandwonglonam/openclaw-session-archiver.git
cd openclaw-session-archiver

# 2. 运行安装
sudo bash install.sh
```

## 配置说明

安装后会创建配置文件：`/etc/openclaw-archiver.conf`

### v2.0 配置（智能压缩）

```bash
# OpenClaw Session Archiver Configuration
# Version: 2.0

# ===== 基础配置 =====
SESSIONS_DIR="/volume1/docker/openclaw/config/agents/main/sessions"
MEMORY_DIR="/volume1/docker/openclaw/config/memory"
WORKSPACE_DIR="/volume1/docker/openclaw/workspace"

# ===== 压缩配置 =====
ENABLE_COMPRESSION=true           # 启用智能压缩
COMPRESSION_THRESHOLD=120         # 120 条消息时触发压缩
COMPRESS_COUNT=80                 # 压缩前 80 条
KEEP_RECENT_MESSAGES=40           # 保留最近 40 条完整消息

# ===== 摘要配置 =====
SUMMARY_MAX_TOKENS=300            # 摘要最大 tokens

# ===== AI 配置 =====
AI_PROVIDER="anthropic"
AI_MODEL="claude-haiku-3-5-20241022"
AI_BASE_URL="https://v3.codesome.cn"
AI_API_KEY=""  # 从环境变量读取：${ANTHROPIC_API_KEY}

# ===== 日志配置 =====
LOG_FILE="/var/log/openclaw-archive.log"
LOG_LEVEL="INFO"  # DEBUG | INFO | WARN | ERROR

# ===== 锁文件 =====
LOCK_FILE="/tmp/openclaw-archive.lock"
```

### v1.0 配置（简单截断）

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

### 配置 API Key（v2.0 必需）

```bash
# 方法 1: 环境变量（推荐）
export ANTHROPIC_API_KEY="your-api-key-here"
echo 'export ANTHROPIC_API_KEY="your-key"' >> ~/.bashrc

# 方法 2: 在 crontab 中配置
sudo crontab -e
# 在文件顶部添加：
ANTHROPIC_API_KEY=your-api-key-here
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

A: **v2.0 不会！** 使用 AI 智能压缩，旧消息被压缩成结构化摘要，保留所有关键信息、决定和偏好。机器人可以通过摘要了解历史上下文，不会"失忆"。

v1.0 可能会有部分上下文丢失，因为使用简单截断。

### Q: AI 压缩的成本是多少？

A: 非常低！使用 Claude Haiku 模型：
- 单次压缩：~$0.002 USD
- 月度成本（10 个活跃 sessions，每个压缩 2 次/月）：~$0.04 USD/月

### Q: 可以禁用 AI 压缩吗？

A: 可以。在配置文件中设置 `ENABLE_COMPRESSION=false`，将回退到 v1.0 的简单截断模式。但不推荐，因为会导致上下文丢失。

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

### AI 智能压缩（v2.0）

**压缩流程**：
1. 检测 session 文件行数
2. 如果超过 `COMPRESSION_THRESHOLD` (120 条)：
   - 提取前 `COMPRESS_COUNT` (80 条) 消息
   - 调用 Claude Haiku API 生成结构化摘要
   - 如果已有摘要，智能合并新旧摘要
   - 保留最近 `KEEP_RECENT_MESSAGES` (40 条) 完整消息
   - 归档原始消息到 memory/ 目录

**摘要格式**：
```markdown
【对话历史摘要】

## 对话主题
[简述主要讨论的话题]

## 关键信息
- [重要信息点 1]
- [重要信息点 2]

## 用户偏好/约定
- [用户的偏好或约定]

## 重要决定
- [做出的决定或计划]

## 待办事项
- [需要跟进的事项]
```

**摘要合并**：
- 当再次触发压缩时，AI 会合并旧摘要和新消息
- 避免产生多个摘要，保持单一连贯的历史记录
- 去除重复信息，保留所有关键内容

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

Created by Roland Wayne

## 更新日志

### v2.0.0 (2026-02-02)
- 🎉 **重大更新：AI 智能压缩**
- ✨ 使用 Claude Haiku 生成结构化摘要
- ✨ 保持上下文连贯性，解决"失忆"问题
- ✨ 智能摘要合并机制
- ✨ 可配置的压缩阈值和保留消息数
- ✨ 详细的日志记录和调试模式
- 📝 完整的测试套件
- 📝 详细的部署文档
- 💰 极低成本：~$0.04/月

### v1.0.0 (2026-02-01)
- 初始版本
- 支持自动归档
- 文件锁机制
- 全局记忆同步
