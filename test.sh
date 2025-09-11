#!/bin/bash

# Warp2Api 快速测试脚本
# 测试启动脚本和基本API功能

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}🚀 Warp2Api 快速测试${NC}"
echo -e "${BLUE}==========================================${NC}"

# 检查脚本是否存在
if [ ! -f "./start.sh" ]; then
    echo -e "${RED}错误: start.sh 脚本不存在${NC}"
    exit 1
fi

if [ ! -f "./stop.sh" ]; then
    echo -e "${RED}错误: stop.sh 脚本不存在${NC}"
    exit 1
fi

echo -e "${YELLOW}正在启动服务器...${NC}"

# 启动服务器（后台运行，超时30秒）
timeout 30s ./start.sh &
START_PID=$!

# 等待几秒让服务器启动
sleep 5

# 检查服务器状态
echo -e "\n${YELLOW}检查服务器状态...${NC}"

BRIDGE_OK=false
OPENAI_OK=false

# 检查Protobuf桥接服务器
if curl -s http://localhost:28888/healthz >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Protobuf桥接服务器 (28888) 运行正常${NC}"
    BRIDGE_OK=true
else
    echo -e "${RED}❌ Protobuf桥接服务器 (28888) 未响应${NC}"
fi

# 检查OpenAI兼容API服务器
if curl -s http://localhost:28889/healthz >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OpenAI兼容API服务器 (28889) 运行正常${NC}"
    OPENAI_OK=true
else
    echo -e "${RED}❌ OpenAI兼容API服务器 (28889) 未响应${NC}"
fi

if [ "$BRIDGE_OK" = true ] && [ "$OPENAI_OK" = true ]; then
    echo -e "\n${GREEN}🎉 服务器启动成功！${NC}"

    # 测试API调用
    echo -e "\n${YELLOW}测试API调用...${NC}"
    RESPONSE=$(curl -s -X POST http://localhost:28889/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{
        "model": "claude-4-sonnet",
        "messages": [{"role": "user", "content": "Say hello in one word"}],
        "max_tokens": 10
      }' | head -c 200)

    if echo "$RESPONSE" | grep -q "data:"; then
        echo -e "${GREEN}✅ API响应正常${NC}"
    else
        echo -e "${YELLOW}⚠️  API响应格式可能有问题${NC}"
    fi

    echo -e "\n${BLUE}测试完成！服务器运行正常。${NC}"
    echo -e "${YELLOW}使用 ./stop.sh 停止服务器${NC}"

else
    echo -e "\n${RED}❌ 服务器启动失败${NC}"
    echo -e "${YELLOW}检查日志文件获取详细信息${NC}"
    exit 1
fi

# 清理后台进程
kill $START_PID 2>/dev/null || true

echo -e "${BLUE}==========================================${NC}"