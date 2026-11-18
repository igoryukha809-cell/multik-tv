@echo off
setlocal
cd /d "%~dp0"
echo ==========================================
echo          MULTIK TV - LOCAL SERVER
echo ==========================================
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker was not found. Install Docker Desktop first:
  echo https://www.docker.com/products/docker-desktop/
  pause
  exit /b 1
)
docker info >nul 2>nul
if errorlevel 1 (
  echo Docker Engine is not running. Start Docker Desktop and try again.
  pause
  exit /b 1
)
if not exist "media" mkdir "media"
echo.
echo Starting SRS and the automatic video playlist...
docker compose up -d --build
if errorlevel 1 (
  echo Server startup failed. Check the Docker error above.
  pause
  exit /b 1
)
echo.
echo Containers:
docker compose ps
echo.
echo Local HLS stream:
echo http://localhost:8080/live/multiktv.m3u8
echo.
echo Opening the channel page...
start "" "http://localhost:8080/live/multiktv.m3u8"
echo.
echo To stop the server, run stop-local.bat
pause
