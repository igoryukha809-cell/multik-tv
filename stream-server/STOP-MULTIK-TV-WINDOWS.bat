@echo off
chcp 65001 >nul
setlocal
title МУЛЬТИК ТВ — остановка сервера
cd /d "%~dp0"
echo Останавливаем контейнеры МУЛЬТИК ТВ...
docker compose down
echo.
echo Сервер остановлен.
pause
