#!/bin/bash

# Warp2Api 停止脚本
# 停止所有相关的服务器进程

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# 停止服务器函数
stop_servers() {
    log_info "正在停止Warp2Api服务器..."

    # 停止Python服务器进程
    log_info "终止Python服务器进程..."
    pkill -f "python3 server.py" 2>/dev/null || true
    pkill -f "python3 openai_compat.py" 2>/dev/null || true

    # 停止端口相关的进程
    log_info "清理端口进程..."
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_info "终止端口8000上的进程..."
        lsof -ti:8000 | xargs kill -9 2>/dev/null || true
    fi

    if lsof -Pi :8010 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_info "终止端口8010上的进程..."
        lsof -ti:8010 | xargs kill -9 2>/dev/null || true
    fi

    # 等待进程完全停止
    sleep 2

    # 验证停止状态
    if ! lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 && ! lsof -Pi :8010 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_success "所有服务器已成功停止"
    else
        log_warning "某些进程可能仍在运行，请手动检查"
    fi

    # 清理日志文件（可选）
    read -p "是否清理日志文件？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f *.log
        log_info "日志文件已清理"
    fi
}

# 显示当前状态
show_status() {
    echo
    echo "=========================================="
    echo "📊 当前服务器状态"
    echo "=========================================="

    # 检查端口8000
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Protobuf桥接服务器 (端口8000): 运行中${NC}"
    else
        echo -e "${RED}❌ Protobuf桥接服务器 (端口8000): 已停止${NC}"
    fi

    # 检查端口8010
    if lsof -Pi :8010 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OpenAI兼容API服务器 (端口8010): 运行中${NC}"
    else
        echo -e "${RED}❌ OpenAI兼容API服务器 (端口8010): 已停止${NC}"
    fi

    echo "=========================================="
}

# 显示帮助信息
show_help() {
    echo "Warp2Api 停止脚本"
    echo
    echo "用法:"
    echo "  ./stop.sh          # 停止所有服务器"
    echo "  ./stop.sh status   # 查看服务器状态"
    echo "  ./stop.sh help     # 显示此帮助信息"
    echo
    echo "功能:"
    echo "  - 安全停止所有Warp2Api相关进程"
    echo "  - 清理端口占用"
    echo "  - 可选清理日志文件"
    echo "  - 显示详细的状态信息"
}

# 主函数
main() {
    case "${1:-}" in
        "status")
            show_status
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            show_status
            stop_servers
            ;;
        *)
            log_error "未知参数: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"