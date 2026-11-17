#!/usr/bin/env bash
set -u
STREAM_URL="${STREAM_URL:-rtmp://srs/live/multiktv}"
shopt -s nullglob
echo "МУЛЬТИК ТВ: поиск видео в /media"
while true; do
  files=(/media/*.mp4 /media/*.mkv /media/*.mov /media/*.webm)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "В /media пока нет видео. Проверка через 30 секунд."
    sleep 30
    continue
  fi
  for file in "${files[@]}"; do
    echo "Передача файла: $file"
    ffmpeg -hide_banner -loglevel warning -re -i "$file" \
      -map 0:v:0 -map 0:a:0? \
      -c:v libx264 -preset veryfast -tune zerolatency \
      -pix_fmt yuv420p -r 25 -g 50 -b:v 1800k -maxrate 1800k -bufsize 3600k \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -f flv "$STREAM_URL" || echo "Не удалось передать $file; перехожу к следующему."
  done
done
