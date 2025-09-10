#!/bin/bash

# Warp2Api 一键启动脚本 (修复版)
# 启动两个服务器：Protobuf桥接服务器和OpenAI兼容API服务器

set -e  # 遇到错误立即退出

# 从 .env 文件加载环境变量（如果存在）
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# 环境变量控制日志输出，默认不打印日志
# 设置 W2A_VERBOSE=true 来启用详细日志输出
VERBOSE="${W2A_VERBOSE:-false}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    fi
}

log_success() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
    fi
}

log_warning() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    fi
}

log_error() {
    # 错误信息始终显示，即使在静默模式下
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# 检查Python版本
check_python() {
    log_info "检查Python版本..."
    if ! command -v python3 &> /dev/null; then
        log_error "未找到python3，请确保Python 3.9+已安装"
        exit 1
    fi

    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    log_info "Python版本: $PYTHON_VERSION"

    # 检查是否为Python 3.9+
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

    if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 9 ]); then
        log_warning "推荐使用Python 3.13+，但当前版本 $PYTHON_VERSION 仍可工作"
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查项目依赖..."

    # 定义需要检查的包
    PACKAGES=("fastapi" "uvicorn" "httpx" "protobuf" "websockets" "openai")
    MISSING_PACKAGES=()

    # 检查每个包
    for package in "${PACKAGES[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            MISSING_PACKAGES+=("$package")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
        log_success "所有依赖包已安装"
        return 0
    fi

    log_warning "缺少以下依赖包: ${MISSING_PACKAGES[*]}"
    log_info "正在尝试自动安装..."

    # 安装缺失的包
    python3 -m pip install "${MISSING_PACKAGES[@]}"
    if [ $? -eq 0 ]; then
        log_success "依赖包安装成功"
    else
        log_error "依赖包安装失败，请手动运行: python3 -m pip install ${MISSING_PACKAGES[*]}"
        exit 1
    fi
}

# 启动Protobuf桥接服务器
start_bridge_server() {
    log_info "启动Protobuf桥接服务器..."

    # 检查端口8000是否被占用
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null ; then
        log_warning "端口8000已被占用，尝试终止现有进程..."
        lsof -ti:8000 | xargs kill -9 2>/dev/null || true
        sleep 2
    fi

    # 启动服务器（后台运行）
    nohup python3 server.py > bridge_server.log 2>&1 &
    BRIDGE_PID=$!

    # 等待服务器启动
    log_info "等待Protobuf桥接服务器启动..."
    for i in {1..30}; do
        if curl -s http://localhost:8000/healthz >/dev/null 2>&1; then
            log_success "Protobuf桥接服务器启动成功 (PID: $BRIDGE_PID)"
            log_info "📍 Protobuf桥接服务器地址: http://localhost:8000"
            return 0
        fi
        sleep 1
    done

    log_error "Protobuf桥接服务器启动失败"
    cat bridge_server.log
    exit 1
}

# 启动OpenAI兼容API服务器
start_openai_server() {
    log_info "启动OpenAI兼容API服务器..."

    # 检查端口8010是否被占用
    if lsof -Pi :8010 -sTCP:LISTEN -t >/dev/null ; then
        log_warning "端口8010已被占用，尝试终止现有进程..."
        lsof -ti:8010 | xargs kill -9 2>/dev/null || true
        sleep 2
    fi

    # 启动服务器（后台运行）
    nohup python3 openai_compat.py > openai_server.log 2>&1 &
    OPENAI_PID=$!

    # 等待服务器启动
    log_info "等待OpenAI兼容API服务器启动..."
    for i in {1..30}; do
        if curl -s http://localhost:8010/healthz >/dev/null 2>&1; then
            log_success "OpenAI兼容API服务器启动成功 (PID: $OPENAI_PID)"
            log_info "📍 OpenAI兼容API服务器地址: http://localhost:8010"
            return 0
        fi
        sleep 1
    done

    log_error "OpenAI兼容API服务器启动失败"
    cat openai_server.log
    exit 1
}

# 显示服务器状态
show_status() {
    echo
    echo "=========================================="
    echo "🚀 Warp2Api 服务器状态"
    echo "=========================================="
    echo "📍 Protobuf桥接服务器: http://localhost:8000"
    echo "📍 OpenAI兼容API服务器: http://localhost:8010"
    echo "📍 API文档: http://localhost:8010/docs"
    echo "🔗 Roocode / KilloCode baseUrl: http://127.0.0.1:8010/v1"
    echo
    echo "🔧 支持的模型:"
    echo "   • claude-4-sonnet"
    echo "   • claude-4-opus"
    echo "   • claude-4.1-opus"
    echo "   • gemini-2.5-pro"
    echo "   • gpt-4.1"
    echo "   • gpt-4o"
    echo "   • gpt-5"
    echo "   • gpt-5 (high reasoning)"
    echo "   • o3"
    echo "   • o4-mini"
    echo
    echo "🔑 当前API接口Token:"
    if [ -f ".env" ]; then
        WARP_JWT=$(grep "^WARP_JWT=" .env | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
        if [ -n "$WARP_JWT" ]; then
            echo "   $WARP_JWT"
        else
            echo "   未设置"
        fi
    else
        echo "   .env 文件不存在"
    fi
    echo
    echo "📝 测试命令:"
    echo "curl -X POST http://localhost:8010/v1/chat/completions \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"model\": \"claude-4-sonnet\", \"messages\": [{\"role\": \"user\", \"content\": \"你好\"}], \"stream\": true}'"
    echo
    echo "🛑 要停止服务器，请运行: ./stop.sh"
    echo "=========================================="
}

# 停止服务器
stop_servers() {
    log_info "停止所有服务器..."

    # 停止所有相关进程
    pkill -f "python3 server.py" 2>/dev/null || true
    pkill -f "python3 openai_compat.py" 2>/dev/null || true

    # 清理可能的僵尸进程
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
    lsof -ti:8010 | xargs kill -9 2>/dev/null || true

    log_success "所有服务器已停止"
}

# 主函数
main() {
    echo "=========================================="
    echo "🚀 Warp2Api 一键启动脚本 (修复版)"
    echo "=========================================="

    # 检查命令行参数
    if [ "$1" = "stop" ]; then
        stop_servers
        exit 0
    fi

    # 检查环境
    check_python
    check_dependencies

    # 启动服务器
    start_bridge_server
    start_openai_server

    # 显示状态信息
    show_status

    if [ "$VERBOSE" = "true" ]; then
        log_success "Warp2Api启动完成！"
        log_info "服务器正在后台运行，按 Ctrl+C 退出"

        # 保持脚本运行，显示日志
        echo
        echo "📋 实时日志监控 (按 Ctrl+C 退出):"
        echo "----------------------------------------"

        # 监控两个服务器的日志
        tail -f bridge_server.log openai_server.log &
        TAIL_PID=$!
    else
        echo "✅ Warp2Api启动完成！服务器正在后台运行。"
        echo "💡 如需查看详细日志，请设置环境变量: export W2A_VERBOSE=true"
        echo "🛑 要停止服务器，请运行: ./stop.sh"
        exit 0
    fi

    # 捕获中断信号
    trap "echo -e '\n${YELLOW}正在停止服务器...${NC}'; stop_servers; kill $TAIL_PID 2>/dev/null; exit 0" INT TERM

    # 等待用户中断
    wait $TAIL_PID
}

# 执行主函数
main "$@"