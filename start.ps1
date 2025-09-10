#Requires -Version 5.1

<#
.SYNOPSIS
    Warp2Api Windows PowerShell 快速启动脚本
.DESCRIPTION
    启动两个服务器：Protobuf桥接服务器和OpenAI兼容API服务器
.PARAMETER Verbose
    启用详细日志输出
.PARAMETER Stop
    停止所有服务器
.EXAMPLE
    .\start.ps1                    # 启动服务器（静默模式）
    .\start.ps1 -Verbose           # 启动服务器（详细模式）
    .\start.ps1 -Stop              # 停止服务器
#>

param(
    [switch]$Verbose,
    [switch]$Stop
)

# 设置控制台编码为UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 从 .env 文件加载环境变量（如果存在）
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($key, $value)
        }
    }
}

# 环境变量控制日志输出，默认不打印日志
$env:W2A_VERBOSE = if ($Verbose) { "true" } else { $env:W2A_VERBOSE ?? "false" }

# 日志函数
function Write-LogInfo {
    param([string]$Message)
    if ($env:W2A_VERBOSE -eq "true") {
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] INFO: $Message" -ForegroundColor Blue
    }
}

function Write-LogSuccess {
    param([string]$Message)
    if ($env:W2A_VERBOSE -eq "true") {
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] SUCCESS: $Message" -ForegroundColor Green
    }
}

function Write-LogWarning {
    param([string]$Message)
    if ($env:W2A_VERBOSE -eq "true") {
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] WARNING: $Message" -ForegroundColor Yellow
    }
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] ERROR: $Message" -ForegroundColor Red
}

# 检查Python版本
function Test-PythonVersion {
    Write-LogInfo "检查Python版本..."

    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "未找到Python，请确保Python 3.9+已安装"
            exit 1
        }

        $versionString = $pythonVersion -replace 'Python ', ''
        Write-LogInfo "Python版本: $versionString"

        $versionParts = $versionString -split '\.'
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]

        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 9)) {
            Write-LogWarning "推荐使用Python 3.13+，但当前版本 $versionString 仍可工作"
        }
    }
    catch {
        Write-LogError "Python检查失败: $($_.Exception.Message)"
        exit 1
    }
}

# 检查依赖
function Test-Dependencies {
    Write-LogInfo "检查项目依赖..."

    $packages = @("fastapi", "uvicorn", "httpx", "protobuf", "websockets", "openai")
    $missingPackages = @()

    foreach ($package in $packages) {
        try {
            python -c "import $package" 2>$null
            if ($LASTEXITCODE -ne 0) {
                $missingPackages += $package
            }
        }
        catch {
            $missingPackages += $package
        }
    }

    if ($missingPackages.Count -eq 0) {
        Write-LogSuccess "所有依赖包已安装"
        return
    }

    Write-LogWarning "缺少以下依赖包: $($missingPackages -join ', ')"
    Write-LogInfo "正在尝试自动安装..."

    try {
        $installResult = python -m pip install $missingPackages
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "依赖包安装成功"
        } else {
            Write-LogError "依赖包安装失败，请手动运行: python -m pip install $($missingPackages -join ' ')"
            exit 1
        }
    }
    catch {
        Write-LogError "依赖包安装失败: $($_.Exception.Message)"
        exit 1
    }
}

# 检查端口是否被占用
function Test-PortAvailable {
    param([int]$Port)

    $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    return $connections.Count -eq 0
}

# 终止端口进程
function Stop-PortProcess {
    param([int]$Port)

    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        foreach ($conn in $connections) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # 忽略错误
    }
}

# 启动Protobuf桥接服务器
function Start-BridgeServer {
    Write-LogInfo "启动Protobuf桥接服务器..."

    # 检查端口8000是否被占用
    if (-not (Test-PortAvailable 8000)) {
        Write-LogWarning "端口8000已被占用，尝试终止现有进程..."
        Stop-PortProcess 8000
        Start-Sleep -Seconds 2
    }

    # 启动服务器（后台运行）
    try {
        $process = Start-Process -FilePath "python" -ArgumentList "server.py" -NoNewWindow -RedirectStandardOutput "bridge_server.log" -RedirectStandardError "bridge_server.log" -PassThru
        $bridgePid = $process.Id

        # 等待服务器启动
        Write-LogInfo "等待Protobuf桥接服务器启动..."
        Start-Sleep -Seconds 5

        # 检查服务器是否启动成功
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8000/healthz" -TimeoutSec 5 -ErrorAction Stop
            Write-LogSuccess "Protobuf桥接服务器启动成功 (PID: $bridgePid)"
            Write-LogInfo "📍 Protobuf桥接服务器地址: http://localhost:8000"
            return $true
        }
        catch {
            Write-LogError "Protobuf桥接服务器启动失败"
            if (Test-Path "bridge_server.log") {
                Get-Content "bridge_server.log" | Write-Host
            }
            return $false
        }
    }
    catch {
        Write-LogError "启动Protobuf桥接服务器失败: $($_.Exception.Message)"
        return $false
    }
}

# 启动OpenAI兼容API服务器
function Start-OpenAIServer {
    Write-LogInfo "启动OpenAI兼容API服务器..."

    # 检查端口8010是否被占用
    if (-not (Test-PortAvailable 8010)) {
        Write-LogWarning "端口8010已被占用，尝试终止现有进程..."
        Stop-PortProcess 8010
        Start-Sleep -Seconds 2
    }

    # 启动服务器（后台运行）
    try {
        $process = Start-Process -FilePath "python" -ArgumentList "openai_compat.py" -NoNewWindow -RedirectStandardOutput "openai_server.log" -RedirectStandardError "openai_server.log" -PassThru
        $openaiPid = $process.Id

        # 等待服务器启动
        Write-LogInfo "等待OpenAI兼容API服务器启动..."
        Start-Sleep -Seconds 5

        # 检查服务器是否启动成功
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8010/healthz" -TimeoutSec 5 -ErrorAction Stop
            Write-LogSuccess "OpenAI兼容API服务器启动成功 (PID: $openaiPid)"
            Write-LogInfo "📍 OpenAI兼容API服务器地址: http://localhost:8010"
            return $true
        }
        catch {
            Write-LogError "OpenAI兼容API服务器启动失败"
            if (Test-Path "openai_server.log") {
                Get-Content "openai_server.log" | Write-Host
            }
            return $false
        }
    }
    catch {
        Write-LogError "启动OpenAI兼容API服务器失败: $($_.Exception.Message)"
        return $false
    }
}

# 显示服务器状态
function Show-Status {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "🚀 Warp2Api 服务器状态"
    Write-Host "============================================"
    Write-Host "📍 Protobuf桥接服务器: http://localhost:8000"
    Write-Host "📍 OpenAI兼容API服务器: http://localhost:8010"
    Write-Host "📍 API文档: http://localhost:8010/docs"
    Write-Host ""
    Write-Host "🔧 支持的模型:"
    Write-Host "   • claude-4-sonnet"
    Write-Host "   • claude-4-opus"
    Write-Host "   • claude-4.1-opus"
    Write-Host "   • gemini-2.5-pro"
    Write-Host "   • gpt-4.1"
    Write-Host "   • gpt-4o"
    Write-Host "   • gpt-5"
    Write-Host "   • gpt-5 (high reasoning)"
    Write-Host "   • o3"
    Write-Host "   • o4-mini"
    Write-Host ""
    Write-Host "📝 测试命令:"
    Write-Host "Invoke-WebRequest -Uri 'http://localhost:8010/v1/chat/completions' -Method POST -ContentType 'application/json' -Body '{\"model\": \"claude-4-sonnet\", \"messages\": [{\"role\": \"user\", \"content\": \"你好\"}], \"stream\": true}'"
    Write-Host ""
    Write-Host "🛑 要停止服务器，请运行: .\stop.ps1"
    Write-Host "============================================"
}

# 停止服务器
function Stop-Servers {
    Write-LogInfo "停止所有服务器..."

    # 停止Python服务器进程
    Write-LogInfo "终止Python服务器进程..."
    Get-Process -Name "python" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # 停止端口相关的进程
    Write-LogInfo "清理端口进程..."
    Stop-PortProcess 8000
    Stop-PortProcess 8010

    Write-LogSuccess "所有服务器已停止"
}

# 主函数
function Main {
    if ($Stop) {
        Stop-Servers
        return
    }

    Write-Host "============================================"
    Write-Host "🚀 Warp2Api PowerShell 快速启动脚本"
    Write-Host "============================================"

    # 检查环境
    Test-PythonVersion
    Test-Dependencies

    # 启动服务器
    $bridgeStarted = Start-BridgeServer
    if (-not $bridgeStarted) {
        Write-LogError "Protobuf桥接服务器启动失败，退出"
        exit 1
    }

    $openaiStarted = Start-OpenAIServer
    if (-not $openaiStarted) {
        Write-LogError "OpenAI兼容API服务器启动失败，退出"
        exit 1
    }

    # 显示状态信息
    Show-Status

    if ($env:W2A_VERBOSE -eq "true") {
        Write-LogSuccess "Warp2Api启动完成！"
        Write-LogInfo "服务器正在后台运行，按 Ctrl+C 退出"

        Write-Host ""
        Write-Host "📋 实时日志监控 (按 Ctrl+C 退出):"
        Write-Host "----------------------------------------"

        # PowerShell 中可以同时监控多个日志文件
        try {
            Get-Content "bridge_server.log", "openai_server.log" -Wait -ErrorAction Stop
        }
        catch {
            Write-Host "日志监控已停止"
        }
    }
    else {
        Write-Host "✅ Warp2Api启动完成！服务器正在后台运行。"
        Write-Host "💡 如需查看详细日志，请使用 -Verbose 参数: .\start.ps1 -Verbose"
        Write-Host "🛑 要停止服务器，请运行: .\stop.ps1"
    }
}

# 执行主函数
Main