#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
BASE_URL="${HLS_BASE_URL:-http://127.0.0.1:8080}"
PLAYLIST_URL="${BASE_URL%/}/live/multiktv.m3u8"
echo "МУЛЬТИК ТВ — локальная диагностика"
echo "Адрес: $PLAYLIST_URL"
echo
if ! command -v curl >/dev/null 2>&1; then
  echo "ОШИБКА: curl не найден. Установи curl и повтори проверку."
  exit 2
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "ОШИБКА: Docker не найден. Установи Docker Desktop/Engine."
  exit 2
fi
if ! docker info >/dev/null 2>&1; then
  echo "ОШИБКА: Docker Engine не запущен."
  exit 2
fi
echo "[1/3] Контейнеры Docker"
docker compose ps
echo
echo "[2/3] Получение HLS-плейлиста"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! curl --fail --silent --show-error --max-time 8 "$PLAYLIST_URL" -o "$TMP"; then
  echo "ОШИБКА: HLS-плейлист недоступен. Проверь docker compose logs srs playlist."
  exit 1
fi
if ! grep -q '^#EXTM3U' "$TMP"; then
  echo "ОШИБКА: ответ не похож на HLS-плейлист."
  exit 1
fi
SEGMENT="$(grep -v '^#' "$TMP" | grep -m1 -v '^[[:space:]]*$' || true)"
if [[ -z "$SEGMENT" ]]; then
  echo "ОШИБКА: HLS-плейлист пока не содержит видеосегментов."
  exit 1
fi
echo "OK: HLS-плейлист получен."
echo
echo "[3/3] Проверка первого видеосегмента"
case "$SEGMENT" in
  http://*|https://*) SEGMENT_URL="$SEGMENT" ;;
  /*) SEGMENT_URL="${BASE_URL%/}$SEGMENT" ;;
  *) SEGMENT_URL="${BASE_URL%/}/live/$SEGMENT" ;;
esac
if curl --fail --silent --show-error --max-time 8 -r 0-0 "$SEGMENT_URL" -o /dev/null; then
  echo "OK: видеосегмент доступен."
else
  echo "ОШИБКА: первый сегмент не загрузился: $SEGMENT_URL"
  exit 1
fi
echo
echo "ДИАГНОСТИКА УСПЕШНА: локальный HLS-поток отвечает."
echo "Это проверка доступности потока, а не юридическая проверка прав на видео."
