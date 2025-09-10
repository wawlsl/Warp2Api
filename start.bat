@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Warp2Api Windows 快速启动脚本
REM 启动两个服务器：Protobuf桥接服务器和OpenAI兼容API服务器

REM 颜色定义 (Windows CMD)
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

REM 从 .env 文件加载环境变量（如果存在）
if exist ".env" (
    for /f "tokens=*" %%i in (.env) do (
        set "%%i"
    )
)

REM 环境变量控制日志输出，默认不打印日志
REM 设置 W2A_VERBOSE=true 来启用详细日志输出
if "%W2A_VERBOSE%"=="" set "W2A_VERBOSE=false"

REM 日志函数
:log_info
if "%W2A_VERBOSE%"=="true" (
    echo %BLUE%[%DATE% %TIME%] INFO: %~1%NC%
)
goto :eof

:log_success
if "%W2A_VERBOSE%"=="true" (
    echo %GREEN%[%DATE% %TIME%] SUCCESS: %~1%NC%
)
goto :eof

:log_warning
if "%W2A_VERBOSE%"=="true" (
    echo %YELLOW%[%DATE% %TIME%] WARNING: %~1%NC%
)
goto :eof

:log_error
echo %RED%[%DATE% %TIME%] ERROR: %~1%NC%
goto :eof

REM 检查Python版本
:check_python
call :log_info "检查Python版本..."
python --version >nul 2>&1
if errorlevel 1 (
    call :log_error "未找到Python，请确保Python 3.9+已安装"
    exit /b 1
)

for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
call :log_info "Python版本: %PYTHON_VERSION%"

REM 检查Python版本号
for /f "tokens=2 delims=." %%a in ("%PYTHON_VERSION%") do set PYTHON_MAJOR=%%a
for /f "tokens=3 delims=." %%a in ("%PYTHON_VERSION%") do set PYTHON_MINOR=%%a

if %PYTHON_MAJOR% lss 3 (
    call :log_warning "推荐使用Python 3.13+，但当前版本 %PYTHON_VERSION% 仍可工作"
) else if %PYTHON_MAJOR%==3 if %PYTHON_MINOR% lss 9 (
    call :log_warning "推荐使用Python 3.13+，但当前版本 %PYTHON_VERSION% 仍可工作"
)
goto :eof

REM 检查依赖
:check_dependencies
call :log_info "检查项目依赖..."

set PACKAGES=fastapi uvicorn httpx protobuf websockets openai
set MISSING_PACKAGES=

for %%p in (%PACKAGES%) do (
    python -c "import %%p" >nul 2>&1
    if errorlevel 1 (
        set MISSING_PACKAGES=!MISSING_PACKAGES! %%p
    )
)

if "!MISSING_PACKAGES!"=="" (
    call :log_success "所有依赖包已安装"
    goto :eof
)

call :log_warning "缺少以下依赖包:!MISSING_PACKAGES!"
call :log_info "正在尝试自动安装..."

REM 安装缺失的包
python -m pip install !MISSING_PACKAGES!
if errorlevel 1 (
    call :log_error "依赖包安装失败，请手动运行: python -m pip install!MISSING_PACKAGES!"
    exit /b 1
) else (
    call :log_success "依赖包安装成功"
)
goto :eof

REM 检查网络连通性
:check_network
call :log_info "检查网络连通性..."

REM 检查 https://app.warp.dev 的连通性
curl -s --connect-timeout 10 --max-time 30 https://app.warp.dev >nul 2>&1
if %errorlevel%==0 (
    call :log_success "网络连通性检查通过"
    echo ✅ 运行时请保证 https://app.warp.dev 网络联通性
) else (
    call :log_warning "网络连通性检查失败，请确保可以访问 https://app.warp.dev"
    echo ⚠️ 运行时请保证 https://app.warp.dev 网络联通性
    echo    如果网络连接失败，服务可能无法正常工作
)
goto :eof

REM 启动Protobuf桥接服务器
:start_bridge_server
call :log_info "启动Protobuf桥接服务器..."

REM 检查端口8000是否被占用
netstat -an | find "8000" >nul 2>&1
if %errorlevel%==0 (
    call :log_warning "端口8000已被占用，尝试终止现有进程..."
    for /f "tokens=5" %%a in ('netstat -ano ^| find "8000"') do (
        taskkill /PID %%a /F >nul 2>&1
    )
    timeout /t 2 >nul
)

REM 启动服务器（后台运行）
start /B python server.py > bridge_server.log 2>&1
set BRIDGE_PID=%errorlevel%

REM 等待服务器启动
call :log_info "等待Protobuf桥接服务器启动..."
timeout /t 5 >nul

curl -s http://localhost:8000/healthz >nul 2>&1
if %errorlevel%==0 (
    call :log_success "Protobuf桥接服务器启动成功 (PID: %BRIDGE_PID%)"
    call :log_info "📍 Protobuf桥接服务器地址: http://localhost:8000"
) else (
    call :log_error "Protobuf桥接服务器启动失败"
    type bridge_server.log
    exit /b 1
)
goto :eof

REM 启动OpenAI兼容API服务器
:start_openai_server
call :log_info "启动OpenAI兼容API服务器..."

REM 检查端口8010是否被占用
netstat -an | find "8010" >nul 2>&1
if %errorlevel%==0 (
    call :log_warning "端口8010已被占用，尝试终止现有进程..."
    for /f "tokens=5" %%a in ('netstat -ano ^| find "8010"') do (
        taskkill /PID %%a /F >nul 2>&1
    )
    timeout /t 2 >nul
)

REM 启动服务器（后台运行）
start /B python openai_compat.py > openai_server.log 2>&1
set OPENAI_PID=%errorlevel%

REM 等待服务器启动
call :log_info "等待OpenAI兼容API服务器启动..."
timeout /t 5 >nul

curl -s http://localhost:8010/healthz >nul 2>&1
if %errorlevel%==0 (
    call :log_success "OpenAI兼容API服务器启动成功 (PID: %OPENAI_PID%)"
    call :log_info "📍 OpenAI兼容API服务器地址: http://localhost:8010"
) else (
    call :log_error "OpenAI兼容API服务器启动失败"
    type openai_server.log
    exit /b 1
)
goto :eof

REM 显示服务器状态
:show_status
echo.
echo ============================================
echo 🚀 Warp2Api 服务器状态
echo ============================================
echo 📍 Protobuf桥接服务器: http://localhost:8000
echo 📍 OpenAI兼容API服务器: http://localhost:8010
echo 📍 API文档: http://localhost:8010/docs
echo 🔗 Roocode / KilloCode baseUrl: http://127.0.0.1:8010/v1
echo.
echo 🔧 支持的模型:http://127.0.0.1:8010/v1/models
echo    • claude-4-sonnet
echo    • claude-4-opus
echo    • claude-4.1-opus
echo    • gemini-2.5-pro
echo    • gpt-4.1
echo    • gpt-4o
echo    • gpt-5
echo    • gpt-5 (high reasoning)
echo    • o3
echo    • o4-mini
echo.
echo 🔑 当前API接口Token:
if exist ".env" (
    for /f "tokens=1,* delims==" %%a in (.env) do (
        if "%%a"=="WARP_JWT" (
            set "WARP_JWT=%%b"
            set "WARP_JWT=!WARP_JWT:"=!"
        )
    )
    if defined WARP_JWT (
        echo    !WARP_JWT!
    ) else (
        echo    未设置
    )
) else (
    echo    .env 文件不存在
)
echo.
echo 📝 测试命令:
echo curl -X POST http://localhost:8010/v1/chat/completions \
echo   -H "Content-Type: application/json" \
echo   -d "{\"model\": \"claude-4-sonnet\", \"messages\": [{\"role\": \"user\", \"content\": \"你好\"}], \"stream\": true}"
echo.
echo 🛑 要停止服务器，请运行: stop.bat
echo ============================================
goto :eof

REM 主函数
:main
echo ============================================
echo 🚀 Warp2Api Windows 快速启动脚本
echo ============================================

REM 检查命令行参数
if "%1"=="stop" goto stop_servers

REM 检查环境
call :check_python
call :check_dependencies
call :check_network

REM 启动服务器
call :start_bridge_server
call :start_openai_server

REM 显示状态信息
call :show_status

if "%W2A_VERBOSE%"=="true" (
    call :log_success "Warp2Api启动完成！"
    call :log_info "服务器正在后台运行，按 Ctrl+C 退出"
    echo.
    echo 📋 实时日志监控 (按 Ctrl+C 退出):
    echo ----------------------------------------
    REM Windows 下没有简单的方式同时监控两个日志文件
    REM 可以建议用户分别查看日志文件
    echo 提示: 可以使用以下命令查看日志:
    echo   • type bridge_server.log
    echo   • type openai_server.log
    pause
) else (
    echo ✅ Warp2Api启动完成！服务器正在后台运行。
    echo 💡 如需查看详细日志，请设置环境变量: set W2A_VERBOSE=true
    echo 🛑 要停止服务器，请运行: stop.bat
)
goto :eof

REM 停止服务器
:stop_servers
call :log_info "停止所有服务器..."

REM 停止Python服务器进程
call :log_info "终止Python服务器进程..."
taskkill /F /IM python.exe >nul 2>&1

REM 停止端口相关的进程
call :log_info "清理端口进程..."
for /f "tokens=5" %%a in ('netstat -ano ^| find "8000"') do (
    taskkill /PID %%a /F >nul 2>&1
)
for /f "tokens=5" %%a in ('netstat -ano ^| find "8010"') do (
    taskkill /PID %%a /F >nul 2>&1
)

call :log_success "所有服务器已停止"
goto :eof

REM 执行主函数
call :main %*