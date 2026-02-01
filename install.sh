#!/bin/bash

# OpenClaw Session Archiver - 安装脚本
# Version: 1.0.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 sudo 运行此脚本"
    exit 1
fi

print_header "OpenClaw Session Archiver - 安装程序"

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif [ "$(uname)" == "Darwin" ]; then
    OS="macos"
else
    OS="unknown"
fi

print_info "检测到系统: $OS"

# 询问配置
print_header "配置向导"

read -p "OpenClaw sessions 目录路径 [/volume1/docker/openclaw/config/agents/main/sessions]: " SESSIONS_DIR
SESSIONS_DIR=${SESSIONS_DIR:-/volume1/docker/openclaw/config/agents/main/sessions}

read -p "归档文件存储目录 [/volume1/docker/openclaw/config/memory]: " MEMORY_DIR
MEMORY_DIR=${MEMORY_DIR:-/volume1/docker/openclaw/config/memory}

read -p "保留的最大消息数 [50]: " MAX_MESSAGES
MAX_MESSAGES=${MAX_MESSAGES:-50}

read -p "OpenClaw workspace 目录 [/volume1/docker/openclaw/workspace]: " WORKSPACE_DIR
WORKSPACE_DIR=${WORKSPACE_DIR:-/volume1/docker/openclaw/workspace}

read -p "定时任务频率 (cron 格式) [0 * * * *]: " CRON_SCHEDULE
CRON_SCHEDULE=${CRON_SCHEDULE:-0 * * * *}

# 验证目录
print_info "验证目录..."
if [ ! -d "$SESSIONS_DIR" ]; then
    print_error "Sessions 目录不存在: $SESSIONS_DIR"
    read -p "是否继续安装? (y/n): " continue
    if [ "$continue" != "y" ]; then
        exit 1
    fi
fi

# 创建配置文件
print_info "创建配置文件..."
cat > /etc/openclaw-archiver.conf << EOF
# OpenClaw Session 归档配置
# 生成时间: $(date)

# Session 文件目录
SESSIONS_DIR="$SESSIONS_DIR"

# 归档文件存储目录
MEMORY_DIR="$MEMORY_DIR"

# 保留的最大消息数
MAX_MESSAGES=$MAX_MESSAGES

# 机器人工作区目录
WORKSPACE_DIR="$WORKSPACE_DIR"

# 定时任务频率
CRON_SCHEDULE="$CRON_SCHEDULE"
EOF

print_success "配置文件已创建: /etc/openclaw-archiver.conf"

# 安装主脚本
print_info "安装归档脚本..."
cp openclaw-archive-sessions.sh /usr/local/bin/
chmod +x /usr/local/bin/openclaw-archive-sessions.sh
print_success "脚本已安装: /usr/local/bin/openclaw-archive-sessions.sh"

# 创建卸载脚本
print_info "创建卸载脚本..."
cat > /usr/local/bin/openclaw-archiver-uninstall.sh << 'EOF'
#!/bin/bash
echo "卸载 OpenClaw Session Archiver..."

# 删除 cron 任务
if [ -f /etc/cron.d/openclaw-archive ]; then
    rm /etc/cron.d/openclaw-archive
    echo "✅ 已删除 cron 任务"
fi

# macOS launchd
if [ -f /Library/LaunchDaemons/com.openclaw.archiver.plist ]; then
    launchctl unload /Library/LaunchDaemons/com.openclaw.archiver.plist
    rm /Library/LaunchDaemons/com.openclaw.archiver.plist
    echo "✅ 已删除 launchd 任务"
fi

# 删除脚本
rm -f /usr/local/bin/openclaw-archive-sessions.sh
rm -f /etc/openclaw-archiver.conf
rm -f /usr/local/bin/openclaw-archiver-uninstall.sh

echo "✅ 卸载完成"
echo "注意: 归档文件未被删除，位于 $MEMORY_DIR"
EOF

chmod +x /usr/local/bin/openclaw-archiver-uninstall.sh
print_success "卸载脚本已创建: /usr/local/bin/openclaw-archiver-uninstall.sh"

# 设置定时任务
print_info "设置定时任务..."

if [ "$OS" == "macos" ]; then
    # macOS 使用 launchd
    cat > /Library/LaunchDaemons/com.openclaw.archiver.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.archiver</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/openclaw-archive-sessions.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/openclaw-archive.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/openclaw-archive.log</string>
</dict>
</plist>
EOF
    launchctl load /Library/LaunchDaemons/com.openclaw.archiver.plist
    print_success "已设置 launchd 定时任务"
else
    # Linux 使用 cron
    echo "$CRON_SCHEDULE root /usr/local/bin/openclaw-archive-sessions.sh >> /var/log/openclaw-archive.log 2>&1" > /etc/cron.d/openclaw-archive
    chmod 644 /etc/cron.d/openclaw-archive
    print_success "已设置 cron 定时任务"
fi

# 测试运行
print_info "测试运行归档脚本..."
/usr/local/bin/openclaw-archive-sessions.sh

print_header "安装完成！"

echo "📋 配置信息:"
echo "  - Sessions 目录: $SESSIONS_DIR"
echo "  - 归档目录: $MEMORY_DIR"
echo "  - 最大消息数: $MAX_MESSAGES"
echo "  - 定时任务: $CRON_SCHEDULE"
echo ""
echo "📝 常用命令:"
echo "  - 查看日志: tail -f /var/log/openclaw-archive.log"
echo "  - 手动运行: sudo /usr/local/bin/openclaw-archive-sessions.sh"
echo "  - 修改配置: sudo nano /etc/openclaw-archiver.conf"
echo "  - 卸载: sudo /usr/local/bin/openclaw-archiver-uninstall.sh"
echo ""
print_success "OpenClaw Session Archiver 已成功安装！"
