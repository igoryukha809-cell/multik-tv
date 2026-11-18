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
    echo "В ${MEDIA_DIR} нет видео. Передаю безопасную тестовую заставку и повторно проверяю каталог через 30 секунд."
    until (( STOP == 1 )) || wget -q -T 3 -O /dev/null http://srs:8080/; do
      echo "Видеосервер SRS пока недоступен; повтор через ${WAIT_SECONDS} секунд."
      sleep "${WAIT_SECONDS}"
    done
    (( STOP == 1 )) && break
    ffmpeg -hide_banner -nostdin -loglevel warning -re \
      -f lavfi -i "color=c=0x172554:s=1280x720:r=25:d=30" \
      -vf "drawtext=fontfile=/usr/share/fonts/TTF/DejaVuSans.ttf:text='MULTIK TV':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2-55,drawtext=fontfile=/usr/share/fonts/TTF/DejaVuSans.ttf:text='TECHNICAL BREAK - TEST SIGNAL':fontcolor=0xFDE68A:fontsize=30:x=(w-text_w)/2:y=(h-text_h)/2+55" \
      -an -c:v libx264 -preset veryfast -tune zerolatency \
      -pix_fmt yuv420p -r 25 -g 50 -b:v 900k -maxrate 900k -bufsize 1800k \
      -f flv "${STREAM_URL}" || echo "Тестовая заставка завершилась; повторяю проверку."
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
