#!/bin/bash

# Warp2Api 对外接口测试脚本
# 只测试对外API接口功能

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}🚀 Warp2Api 对外接口测试${NC}"
echo -e "${BLUE}==========================================${NC}"

# 检查API服务器是否运行
echo -e "${YELLOW}检查API服务器状态...${NC}"

if curl -s http://localhost:28889/healthz >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OpenAI兼容API服务器 (28889) 运行正常${NC}"
else
    echo -e "${RED}❌ OpenAI兼容API服务器 (28889) 未响应${NC}"
    echo -e "${YELLOW}请先运行 ./start.sh 启动服务器${NC}"
    exit 1
fi

# 测试API接口
echo -e "\n${YELLOW}测试API接口...${NC}"

# 获取API Token
API_TOKEN=""
if [ -f ".env" ]; then
    API_TOKEN=$(grep "^API_TOKEN=" .env | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
fi

if [ -z "$API_TOKEN" ]; then
    API_TOKEN="0000"
    echo -e "${YELLOW}⚠️  未找到API_TOKEN，使用默认值: $API_TOKEN${NC}"
fi

# 测试chat completions接口
echo -e "${BLUE}测试 /v1/chat/completions 接口...${NC}"
RESPONSE=$(curl -s -X POST http://localhost:28889/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "model": "claude-4-sonnet",
    "messages": [{"role": "user", "content": "Say hello in one word"}],
    "max_tokens": 10,
    "stream": false
  }')

if echo "$RESPONSE" | grep -q '"choices"'; then
    echo -e "${GREEN}✅ Chat completions 接口正常${NC}"
else
    echo -e "${RED}❌ Chat completions 接口异常${NC}"
    echo -e "${YELLOW}响应内容: $RESPONSE${NC}"
fi

# 测试models接口
echo -e "${BLUE}测试 /v1/models 接口...${NC}"
MODELS_RESPONSE=$(curl -s http://localhost:28889/v1/models)

if echo "$MODELS_RESPONSE" | grep -q '"data"'; then
    echo -e "${GREEN}✅ Models 接口正常${NC}"
else
    echo -e "${RED}❌ Models 接口异常${NC}"
    echo -e "${YELLOW}响应内容: $MODELS_RESPONSE${NC}"
fi

echo -e "\n${GREEN}🎉 对外接口测试完成！${NC}"
echo -e "${BLUE}==========================================${NC}"