@echo off
chcp 65001 >nul
setlocal
title МУЛЬТИК ТВ — запуск локального видеосервера
cd /d "%~dp0"

echo ============================================
echo          МУЛЬТИК ТВ — ЗАПУСК СЕРВЕРА
echo ============================================
echo.
echo Проверяем Docker...
docker version >nul 2>&1
if errorlevel 1 (
  echo ОШИБКА: Docker не запущен или не установлен.
  echo Установи Docker Desktop и дождись запуска Docker Engine.
  echo https://www.docker.com/products/docker-desktop/
  echo.
  pause
  exit /b 1
)

if not exist "media" mkdir "media"
echo.
echo Видео для эфира должны находиться в папке:
echo %CD%\media
echo Добавляй только свои видео или материалы с письменным разрешением
echo на публичную онлайн-трансляцию.
echo.
echo Запускаем SRS и автоматический плейлист...
docker compose up -d --build
if errorlevel 1 (
  echo.
  echo Не удалось запустить сервер. Проверь сообщения Docker выше.
  pause
  exit /b 1
)

echo.
echo Состояние контейнеров:
docker compose ps
echo.
echo Локальный HLS-плеер:
echo http://localhost:8080/live/multiktv.m3u8
echo.
echo ВАЖНО:
echo - Это локальный тест в домашней сети, а не публичный эфир в интернете.
echo - Компьютер и Docker должны оставаться включёнными.
echo - Не открывай порты роутера и не публикуй домашний IP.
echo - Для настройки публичного доступа нужен взрослый и защищённая инфраструктура.
echo.
echo Для просмотра логов выполни: docker compose logs -f
echo Для остановки запусти STOP-MULTIK-TV-WINDOWS.bat
echo.
pause
