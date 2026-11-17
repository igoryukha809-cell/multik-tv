#!/usr/bin/env bash
set -Eeuo pipefail

STREAM_URL="${STREAM_URL:-rtmp://srs/live/multiktv}"
MEDIA_DIR="${MEDIA_DIR:-/media}"
RETRY_SECONDS="${RETRY_SECONDS:-10}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"
STOP=0

stop() { STOP=1; echo "МУЛЬТИК ТВ: получена команда остановки"; }
trap stop TERM INT

shopt -s nullglob
echo "МУЛЬТИК ТВ: автоматический плейлист запущен; каталог: ${MEDIA_DIR}"

while (( STOP == 0 )); do
  files=("${MEDIA_DIR}"/*.mp4 "${MEDIA_DIR}"/*.mkv "${MEDIA_DIR}"/*.mov "${MEDIA_DIR}"/*.webm)

  if (( ${#files[@]} == 0 )); then
    echo "В ${MEDIA_DIR} нет видео. Повторная проверка через 30 секунд."
    for ((i=0; i<30 && STOP==0; i++)); do sleep 1; done
    continue
  fi

  for file in "${files[@]}"; do
    (( STOP == 1 )) && break
    [[ -f "$file" ]] || continue

    # Wait until the SRS HTTP endpoint responds before attempting RTMP ingest.
    until (( STOP == 1 )) || wget -q -T 3 -O /dev/null http://srs:8080/; do
      echo "Видеосервер SRS пока недоступен; повтор через ${WAIT_SECONDS} секунд."
      sleep "$WAIT_SECONDS"
    done
    (( STOP == 1 )) && break

    echo "Эфир: ${file}"
    if ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$file" \
      -map 0:v:0 -map 0:a:0? \
      -c:v libx264 -preset veryfast -tune zerolatency \
      -pix_fmt yuv420p -r 25 -g 50 -b:v 1800k -maxrate 1800k -bufsize 3600k \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "$STREAM_URL"; then
      echo "Файл завершён: ${file}"
    else
      echo "Ошибка передачи ${file}; пропускаю файл и продолжаю плейлист."
    fi
  done

  # Brief pause prevents a tight error loop if every source file is damaged.
  (( STOP == 1 )) || sleep "$RETRY_SECONDS"
done

echo "МУЛЬТИК ТВ: плейлист остановлен."
