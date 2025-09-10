@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM Warp2Api Windows 停止脚本
REM 停止所有相关的服务器进程

REM 颜色定义 (Windows CMD)
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

REM 日志函数
:log_info
echo %BLUE%[%DATE% %TIME%] INFO: %~1%NC%
goto :eof

:log_success
echo %GREEN%[%DATE% %TIME%] SUCCESS: %~1%NC%
goto :eof

:log_warning
echo %YELLOW%[%DATE% %TIME%] WARNING: %~1%NC%
goto :eof

:log_error
echo %RED%[%DATE% %TIME%] ERROR: %~1%NC%
goto :eof

REM 显示当前状态
:show_status
echo.
echo ============================================
echo 📊 当前服务器状态
echo ============================================

REM 检查端口8000
netstat -an | find "8000" >nul 2>&1
if %errorlevel%==0 (
    echo ✅ Protobuf桥接服务器 (端口8000): 运行中
) else (
    echo ❌ Protobuf桥接服务器 (端口8000): 已停止
)

REM 检查端口8010
netstat -an | find "8010" >nul 2>&1
if %errorlevel%==0 (
    echo ✅ OpenAI兼容API服务器 (端口8010): 运行中
) else (
    echo ❌ OpenAI兼容API服务器 (端口8010): 已停止
)

echo ============================================
goto :eof

REM 停止服务器函数
:stop_servers
call :log_info "正在停止Warp2Api服务器..."

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

REM 等待进程完全停止
timeout /t 2 >nul

REM 验证停止状态
netstat -an | find "8000" >nul 2>&1
set PORT_8000_RUNNING=%errorlevel%
netstat -an | find "8010" >nul 2>&1
set PORT_8010_RUNNING=%errorlevel%

if %PORT_8000_RUNNING%==1 if %PORT_8010_RUNNING%==1 (
    call :log_success "所有服务器已成功停止"
) else (
    call :log_warning "某些进程可能仍在运行，请手动检查"
)

REM 清理日志文件（可选）
set /p choice="是否清理日志文件？(y/N): "
if /i "!choice!"=="y" (
    del *.log 2>nul
    call :log_info "日志文件已清理"
)
goto :eof

REM 显示帮助信息
:show_help
echo Warp2Api Windows 停止脚本
echo.
echo 用法:
echo   stop.bat          # 停止所有服务器
echo   stop.bat status   # 查看服务器状态
echo   stop.bat help     # 显示此帮助信息
echo.
echo 功能:
echo   - 安全停止所有Warp2Api相关进程
echo   - 清理端口占用
echo   - 可选清理日志文件
echo   - 显示详细的状态信息
goto :eof

REM 主函数
:main
if "%1"=="status" (
    call :show_status
) else if "%1"=="help" (
    call :show_help
) else if "%1"=="" (
    call :show_status
    call :stop_servers
) else (
    call :log_error "未知参数: %1"
    echo.
    call :show_help
    exit /b 1
)
goto :eof

REM 执行主函数
call :main %*