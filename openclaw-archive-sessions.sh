#!/bin/bash

# OpenClaw Session 智能压缩归档脚本
# Version: 2.0
# Description: 使用 AI 压缩旧消息，保持上下文连贯性

set -euo pipefail

# ===== 加载配置 =====
CONFIG_FILE="${CONFIG_FILE:-/etc/openclaw-archiver.conf}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# ===== 全局变量 =====
SCRIPT_NAME="OpenClaw Archiver v2"
GLOBAL_MEMORY="$MEMORY_DIR/global_memory.md"

# 统计变量
total_sessions=0
compressed_sessions=0
total_compressed_messages=0
total_api_calls=0

# ===== 日志函数 =====
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_debug() { [ "$LOG_LEVEL" = "DEBUG" ] && log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ===== 文件锁 =====
acquire_lock() {
    exec 200>"$LOCK_FILE"
    flock -n 200 || {
        log_warn "Another instance is running. Exiting."
        exit 1
    }
}

# ===== AI API 调用 =====
call_ai_api() {
    local prompt=$1
    local max_tokens=${2:-$SUMMARY_MAX_TOKENS}

    # 使用环境变量或配置文件中的 API key
    local api_key="${AI_API_KEY:-${ANTHROPIC_API_KEY}}"

    if [ -z "$api_key" ]; then
        log_error "AI_API_KEY not set"
        return 1
    fi

    log_debug "Calling AI API: model=$AI_MODEL, max_tokens=$max_tokens"

    local response=$(curl -s -w "\n%{http_code}" "$AI_BASE_URL/v1/messages" \
        -H "x-api-key: $api_key" \
        -H "content-type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"$AI_MODEL\",
            \"max_tokens\": $max_tokens,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": $(echo "$prompt" | jq -Rs .)
            }]
        }")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "AI API call failed: HTTP $http_code"
        log_debug "Response: $body"
        return 1
    fi

    total_api_calls=$((total_api_calls + 1))

    # 提取文本内容
    echo "$body" | jq -r '.content[0].text' 2>/dev/null || {
        log_error "Failed to parse AI response"
        return 1
    }
}

# ===== 生成摘要 =====
generate_summary() {
    local messages=$1
    local message_count=$(echo "$messages" | wc -l)

    log_info "Generating summary for $message_count messages..."

    # 构建提示词
    local prompt="你是一个专业的对话摘要助手。请将以下对话压缩成结构化摘要。

要求：
1. 保留所有关键信息、决定和约定
2. 保留用户的偏好和特殊需求
3. 保留重要的上下文和背景
4. 使用清晰的结构化格式
5. 控制在 300 tokens 以内

摘要格式：
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

对话内容（JSONL 格式）：
$messages"

    call_ai_api "$prompt"
}

# ===== 合并摘要 =====
merge_summaries() {
    local old_summary=$1
    local new_messages=$2
    local new_message_count=$(echo "$new_messages" | wc -l)

    log_info "Merging existing summary with $new_message_count new messages..."

    local prompt="你是一个专业的对话摘要助手。请将以下旧摘要和新对话合并成一个更新的摘要。

要求：
1. 保留旧摘要中的所有重要信息
2. 整合新对话中的关键内容
3. 去除重复信息
4. 保持结构化格式
5. 控制在 300 tokens 以内

旧摘要：
$old_summary

新对话（JSONL 格式）：
$new_messages

请生成合并后的摘要："

    call_ai_api "$prompt"
}

# ===== 检查是否有摘要 =====
has_summary() {
    local session_file=$1
    local first_line=$(head -n 1 "$session_file")

    echo "$first_line" | jq -e '.content' 2>/dev/null | grep -q "【对话历史摘要】"
}

# ===== 提取摘要内容 =====
extract_summary() {
    local session_file=$1
    head -n 1 "$session_file" | jq -r '.content' | sed 's/【对话历史摘要】//' | sed 's/---.*$//'
}

# ===== 压缩 Session =====
compress_session() {
    local session_file=$1
    local session_id=$(basename "$session_file" .jsonl)
    local message_count=$(wc -l < "$session_file")

    log_info "Processing session: $session_id ($message_count messages)"

    # 检查是否需要压缩
    if [ "$message_count" -le "$COMPRESSION_THRESHOLD" ]; then
        log_debug "Session $session_id below threshold, skipping"
        return 0
    fi

    # 使用文件锁避免冲突
    (
        flock -w 10 200 || {
            log_warn "Cannot lock $session_file, skipping"
            return 1
        }

        log_info "Compressing session $session_id..."

        # 检查是否已有摘要
        local has_existing_summary=false
        local old_summary=""

        if has_summary "$session_file"; then
            has_existing_summary=true
            old_summary=$(extract_summary "$session_file")
            log_debug "Found existing summary in session"
        fi

        # 提取要压缩的消息
        local compress_count=$COMPRESS_COUNT
        local old_messages

        if [ "$has_existing_summary" = true ]; then
            # 跳过第一行（摘要），提取后续消息
            old_messages=$(tail -n +2 "$session_file" | head -n "$compress_count")
        else
            # 直接提取前 N 条
            old_messages=$(head -n "$compress_count" "$session_file")
        fi

        # 生成或合并摘要
        local summary
        if [ "$has_existing_summary" = true ]; then
            summary=$(merge_summaries "$old_summary" "$old_messages")
        else
            summary=$(generate_summary "$old_messages")
        fi

        if [ -z "$summary" ]; then
            log_error "Failed to generate summary for session $session_id"
            return 1
        fi

        log_debug "Summary generated successfully"

        # 创建摘要消息（JSONL 格式）
        local timestamp=$(date +%s)
        local summary_message=$(jq -n \
            --arg id "summary-$timestamp" \
            --arg content "【对话历史摘要】

$summary

---
以上是早期对话的压缩摘要（原始记录已归档）。
压缩时间：$(date '+%Y-%m-%d %H:%M:%S')
压缩消息数：$compress_count 条" \
            '{
                type: "message",
                id: $id,
                role: "system",
                content: $content,
                timestamp: now | tostring
            }')

        # 保留最近的消息
        local keep_messages=$(tail -n "$KEEP_RECENT_MESSAGES" "$session_file")

        # 创建新 session 文件
        local temp_file="${session_file}.compressed.$$"
        {
            echo "$summary_message"
            echo "$keep_messages"
        } > "$temp_file"

        # 归档原始消息
        local archive_file="$MEMORY_DIR/${session_id}_archive_$(date +%Y%m%d_%H%M%S).jsonl"
        if [ "$has_existing_summary" = true ]; then
            tail -n +2 "$session_file" | head -n "$compress_count" > "$archive_file"
        else
            head -n "$compress_count" "$session_file" > "$archive_file"
        fi

        log_info "Archived $compress_count messages to $(basename "$archive_file")"

        # 替换原文件
        mv "$temp_file" "$session_file"

        # 更新统计
        local new_count=$(wc -l < "$session_file")
        compressed_sessions=$((compressed_sessions + 1))
        total_compressed_messages=$((total_compressed_messages + compress_count))

        log_info "Compression complete: $message_count → $new_count messages"

    ) 200>"${session_file}.lock"
}

# ===== 主函数 =====
main() {
    log_info "========================================="
    log_info "$SCRIPT_NAME started"
    log_info "========================================="

    # 获取文件锁
    acquire_lock

    # 创建目录
    mkdir -p "$MEMORY_DIR"

    # 初始化 global_memory.md
    if [ ! -f "$GLOBAL_MEMORY" ]; then
        cat > "$GLOBAL_MEMORY" << 'EOF'
# OpenClaw Global Memory
# 这个文件包含所有归档的对话历史，供机器人参考

## 说明
- 本文件由自动归档系统生成
- 使用智能压缩技术，保持上下文连贯性
- 机器人可以参考这些历史来保持长期记忆

---

EOF
        log_info "Initialized global_memory.md"
    fi

    # 遍历所有 session 文件
    for session_file in "$SESSIONS_DIR"/*.jsonl; do
        [ -f "$session_file" ] || continue

        total_sessions=$((total_sessions + 1))

        if [ "$ENABLE_COMPRESSION" = true ]; then
            compress_session "$session_file" || log_warn "Failed to compress $(basename "$session_file")"
        fi
    done

    # 清理旧的 lock 文件
    find /tmp -name "*.lock" -mtime +30 -delete 2>/dev/null

    # 输出统计信息
    log_info "========================================="
    log_info "Archive completed:"
    log_info "  - Total sessions: $total_sessions"
    log_info "  - Compressed sessions: $compressed_sessions"
    log_info "  - Total compressed messages: $total_compressed_messages"
    log_info "  - AI API calls: $total_api_calls"
    log_info "  - Global memory: $GLOBAL_MEMORY"
    log_info "========================================="
}

# ===== 执行 =====
main "$@"
exit 0
