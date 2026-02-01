#!/bin/bash

# OpenClaw Session 自动归档脚本
# Version: 1.0.0
# Description: 自动归档超过阈值的 session 消息，保持 API 快速响应

# 加载配置文件
CONFIG_FILE="/etc/openclaw-archiver.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # 默认配置
    SESSIONS_DIR="${SESSIONS_DIR:-/volume1/docker/openclaw/config/agents/main/sessions}"
    MEMORY_DIR="${MEMORY_DIR:-/volume1/docker/openclaw/config/memory}"
    MAX_MESSAGES="${MAX_MESSAGES:-50}"
    WORKSPACE_DIR="${WORKSPACE_DIR:-/volume1/docker/openclaw/workspace}"
fi

GLOBAL_MEMORY="$MEMORY_DIR/global_memory.md"
LOCK_FILE="/tmp/openclaw-archive.lock"
LOG_PREFIX="[OpenClaw Archiver]"

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

# 使用 flock 确保同一时间只有一个实例运行
exec 200>"$LOCK_FILE"
flock -n 200 || { log "Another instance is running. Exiting."; exit 1; }

# 创建 memory 目录
mkdir -p "$MEMORY_DIR"

# 初始化 global_memory.md
if [ ! -f "$GLOBAL_MEMORY" ]; then
    cat > "$GLOBAL_MEMORY" << 'EOFMEMORY'
# OpenClaw Global Memory
# 这个文件包含所有归档的对话历史，供机器人参考

## 说明
- 本文件由自动归档系统生成
- 包含超过阈值后被归档的历史对话
- 机器人可以参考这些历史来保持长期记忆

---

EOFMEMORY
    log "Initialized global_memory.md"
fi

# 统计变量
total_sessions=0
archived_sessions=0
total_archived_messages=0

# 遍历所有 session 文件
for session_file in "$SESSIONS_DIR"/*.jsonl; do
    [ -f "$session_file" ] || continue

    total_sessions=$((total_sessions + 1))
    session_id=$(basename "$session_file" .jsonl)

    # 使用 flock 锁定 session 文件，避免与 OpenClaw 冲突
    (
        flock -w 10 200 || { log "Cannot lock $session_file, skipping"; exit 1; }

        message_count=$(wc -l < "$session_file")

        # 如果消息数超过 MAX_MESSAGES
        if [ "$message_count" -gt "$MAX_MESSAGES" ]; then
            log "Session $session_id has $message_count messages, archiving..."

            # 计算需要归档的消息数
            archive_count=$((message_count - MAX_MESSAGES))

            # 创建 session 专属 memory 文件
            memory_file="$MEMORY_DIR/${session_id}_memory.md"

            # 添加归档时间戳
            {
                echo ""
                echo "## Archived at $(date)"
                echo "Session ID: $session_id"
                echo "Messages archived: $archive_count"
                echo "Remaining messages: $MAX_MESSAGES"
                echo ""
            } >> "$memory_file"

            # 归档旧消息
            head -n "$archive_count" "$session_file" >> "$memory_file"

            # 同时追加到 global_memory.md
            {
                echo ""
                echo "### Session $session_id - $(date)"
                echo "Archived $archive_count messages"
                echo ""
                head -n "$archive_count" "$session_file" | tail -n 10  # 只保留最后10条到全局记忆
            } >> "$GLOBAL_MEMORY"

            # 保留最近的 MAX_MESSAGES 条消息
            tail -n "$MAX_MESSAGES" "$session_file" > "${session_file}.tmp"
            mv "${session_file}.tmp" "$session_file"

            archived_sessions=$((archived_sessions + 1))
            total_archived_messages=$((total_archived_messages + archive_count))

            log "Archived $archive_count messages from session $session_id"
        fi
    ) 200>"${session_file}.lock"
done

# 更新 MEMORY.md（如果存在）
if [ -d "$WORKSPACE_DIR" ] && [ -f "$WORKSPACE_DIR/MEMORY.md" ]; then
    if [ -f "$GLOBAL_MEMORY" ]; then
        # 检查是否已经添加过归档历史部分
        if ! grep -q "## Archived Conversation History" "$WORKSPACE_DIR/MEMORY.md"; then
            cat >> "$WORKSPACE_DIR/MEMORY.md" << 'EOFMEM'

---

## Archived Conversation History

以下是归档的对话历史摘要。当需要回忆过去的对话时，可以参考这些内容。

EOFMEM
            # 添加最近的归档内容（最后 50 行）
            tail -n 50 "$GLOBAL_MEMORY" >> "$WORKSPACE_DIR/MEMORY.md"
            log "Updated MEMORY.md with archived history"
        fi
    fi
fi

# 清理超过 30 天的 lock 文件
find /tmp -name "*.lock" -mtime +30 -delete 2>/dev/null

# 输出统计信息
log "Archive completed:"
log "  - Total sessions: $total_sessions"
log "  - Archived sessions: $archived_sessions"
log "  - Total archived messages: $total_archived_messages"
log "  - Global memory: $GLOBAL_MEMORY"

exit 0
