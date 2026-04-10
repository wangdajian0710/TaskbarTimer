@echo off
chcp 65001 >nul
echo ========================================
echo   TaskbarTimer 一键同步脚本
echo ========================================
echo.

set "REPO_DIR=E:\计时器"
set "PKG_DIR=E:\计时器\TaskbarTimer"
set "GIT="C:\Program Files\Git\bin\git.exe""

echo [1/4] 同步到打包目录...
copy /Y "%REPO_DIR%\TaskbarTimer.ps1" "%PKG_DIR%\TaskbarTimer.ps1"
echo   OK

echo [2/4] 刷新桌面 zip...
powershell -Command "Compress-Archive -Path '%PKG_DIR%\*' -DestinationPath '%USERPROFILE%\Desktop\TaskbarTimer.zip' -Force"
echo   OK

echo [3/4] Git 提交...
%GIT% -C "%REPO_DIR%" add -A
%GIT% -C "%REPO_DIR%" commit -m "auto-sync %date% %time%"
echo   OK

echo [4/4] Push 到 GitHub...
%GIT% -C "%REPO_DIR%" push -u origin main
echo   OK

echo.
echo ========================================
echo   全部同步完成！
echo ========================================
pause
