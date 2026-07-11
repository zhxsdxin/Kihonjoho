@echo off
chcp 65001 >nul
echo ========================================
echo  基本情報技術者 過去問題 ローカルサーバー
echo ========================================
echo.

:: 尝试 Python
python --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Python 使用中 ...
    start http://localhost:8080
    python -m http.server 8080
    pause
    exit /b
)

:: 尝试 Node
node --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Node.js 使用中 ...
    npx serve . --port 8080 --no-open
    pause
    exit /b
)

echo [ERR] 未找到 Python 或 Node.js，请安装:
echo   Python: https://www.python.org/downloads/
echo.
pause
