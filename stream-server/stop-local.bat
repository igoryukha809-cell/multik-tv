@echo off
setlocal
cd /d "%~dp0"
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker was not found.
  pause
  exit /b 1
)
docker compose down
echo.
echo MULTIK TV local server stopped.
pause
