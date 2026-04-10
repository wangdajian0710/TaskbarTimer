@echo off
chcp 65001 >nul
echo.
echo ================================
echo    Taskbar Timer - 任务栏计时器
echo ================================
echo.
echo 正在启动...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0TaskbarTimer.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo 启动失败，请右键 TaskbarTimer.ps1 选择"使用 PowerShell 运行"
    echo.
    pause
)
