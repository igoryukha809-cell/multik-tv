#!/usr/bin/env bash
set -Eeuo pipefail

STREAM_URL="${STREAM_URL:-rtmp://srs/live/multiktv}"
MEDIA_DIR="${MEDIA_DIR:-/media}"
RETRY_SECONDS="${RETRY_SECONDS:-10}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"
STOP=0
stop() { STOP=1; echo "МУЛЬТИК ТВ: получена команда остановки"; }
trap stop TERM INT

srs_ready() { (echo > /dev/tcp/srs/1935) >/dev/null 2>&1; }
wait_for_srs() {
  until (( STOP == 1 )) || srs_ready; do
    echo "SRS пока недоступен; повтор через ${WAIT_SECONDS} секунд."
    sleep "${WAIT_SECONDS}"
  done
  (( STOP == 1 )) && return 1
  return 0
}

# playlist.txt is an optional UTF-8 list of basenames, one per line.
# The file is authored locally and mounted read-only into this container.
load_media() {
  local entry ext
  local -a ordered=()
  if [[ -f "${MEDIA_DIR}/playlist.txt" ]]; then
    while IFS= read -r entry || [[ -n "$entry" ]]; do
      entry="${entry%$'\r'}"
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      # Accept only a basename; never follow directories or path traversal.
      [[ "$entry" != */* && "$entry" != *\\* && "$entry" != "." && "$entry" != ".." ]] || {
        echo "Пропускаю недопустимую строку плейлиста: $entry" >&2
        continue
      }
      ext="${entry##*.}"
      case "${ext,,}" in mp4|mkv|mov|webm) ;; *) echo "Неподдерживаемый формат в playlist.txt: $entry" >&2; continue ;; esac
      [[ -f "${MEDIA_DIR}/$entry" ]] || { echo "Файл из плейлиста не найден: $entry" >&2; continue; }
      ordered+=("${MEDIA_DIR}/$entry")
    done < "${MEDIA_DIR}/playlist.txt"
  fi
  if (( ${#ordered[@]} > 0 )); then
    printf '%s\\n' "${ordered[@]}"
  else
    local -a discovered=()
    shopt -s nullglob
    discovered=("${MEDIA_DIR}"/*.mp4 "${MEDIA_DIR}"/*.mkv "${MEDIA_DIR}"/*.mov "${MEDIA_DIR}"/*.webm)
    shopt -u nullglob
    printf '%s\\n' "${discovered[@]}"
  fi
}

echo "МУЛЬТИК ТВ: автоматический плейлист запущен; каталог: ${MEDIA_DIR}"
while (( STOP == 0 )); do
  mapfile -t files < <(load_media)
  if (( ${#files[@]} == 0 )); then
    echo "Видео не найдены. Передаю техническую тестовую заставку."
    wait_for_srs || break
    ffmpeg -hide_banner -nostdin -loglevel warning -re \
      -f lavfi -i "color=c=0x172554:s=1280x720:r=25:d=30" \
      -vf "drawtext=fontfile=/usr/share/fonts/TTF/DejaVuSans.ttf:text='MULTIK TV':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2-55,drawtext=fontfile=/usr/share/fonts/TTF/DejaVuSans.ttf:text='TECHNICAL BREAK - TEST SIGNAL':fontcolor=0xFDE68A:fontsize=30:x=(w-text_w)/2:y=(h-text_h)/2+55" \
      -an -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 900k -maxrate 900k -bufsize 1800k \
      -f flv "${STREAM_URL}" || echo "Тестовый сигнал завершён; повторяю проверку."
    continue
  fi
  for file in "${files[@]}"; do
    (( STOP == 1 )) && break
    [[ -f "$file" ]] || continue
    wait_for_srs || break
    echo "Эфир: ${file##*/}"
    if ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$file" \
      -map 0:v:0 -map 0:a:0? -c:v libx264 -preset veryfast -tune zerolatency \
      -pix_fmt yuv420p -r 25 -g 50 -b:v 1800k -maxrate 1800k -bufsize 3600k \
      -c:a aac -b:a 128k -ar 44100 -ac 2 -f flv "$STREAM_URL"; then
      echo "Файл завершён: ${file##*/}"
    else
      echo "Ошибка передачи ${file##*/}; пропускаю файл."
    fi
  done
  (( STOP == 1 )) || sleep "${RETRY_SECONDS}"
done
echo "МУЛЬТИК ТВ: плейлист остановлен."
