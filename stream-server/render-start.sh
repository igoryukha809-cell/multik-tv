#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs

HTTP_PORT="${PORT:-10000}"
PROGRAM_VIDEO_URL="${PROGRAM_VIDEO_URL:-}"
PROGRAM_RIGHTS_CONFIRMED="${PROGRAM_RIGHTS_CONFIRMED:-false}"
PROGRAM_FILE="/tmp/multik-tv-program.webm"
DOWNLOAD_LOG="/tmp/multik-tv-download.log"
WEATHER_TIME="${WEATHER_TIME:-10:00}"
export TZ="${BROADCAST_TZ:-Europe/Moscow}"
WEATHER_DIR="/tmp/multik-tv-weather"
WEATHER_VIDEO="/tmp/multik-tv-weather-show.mp4"
ORIGINAL_DIR="/usr/local/srs/originals"
CAPTION_DIR="/usr/local/srs/objs/nginx/html/captions"
WEATHER_FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
  echo "Invalid PORT value: $HTTP_PORT" >&2
  exit 1
fi

sed -E "s/^([[:space:]]*listen[[:space:]]+)8080;/\\1${HTTP_PORT};/" conf/multik-tv.conf > conf/render.conf
./objs/srs -c conf/render.conf &
SRS_PID=$!
FFMPEG_PID=""
DOWNLOAD_PID=""

cleanup() {
  [[ -z "$FFMPEG_PID" ]] || kill "$FFMPEG_PID" 2>/dev/null || true
  [[ -z "$DOWNLOAD_PID" ]] || kill "$DOWNLOAD_PID" 2>/dev/null || true
  kill "$SRS_PID" 2>/dev/null || true
  wait || true
}
trap cleanup TERM INT

until (echo >/dev/tcp/127.0.0.1/1935) >/dev/null 2>&1; do
  kill -0 "$SRS_PID" 2>/dev/null || { echo "SRS failed to start"; exit 1; }
  sleep 2
done

echo "SRS ready on HTTP port $HTTP_PORT."
echo "Starting an explicit technical test signal while the open-license program downloads."

play_maintenance_slate() {
  echo "В эфире: профилактическая заставка после запуска сервера."
  ffmpeg -hide_banner -nostdin -loglevel warning -re -loop 1 -framerate 25 \
    -i /usr/local/srs/maintenance.png \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawtext=fontfile=${WEATHER_FONT}:text='УВАЖАЕМЫЕ ЗРИТЕЛИ!':fontcolor=0xffe65a:fontsize=58:x=(w-text_w)/2:y=205:shadowcolor=black@0.35:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:text='НА КАНАЛЕ ПРОВОДЯТСЯ':fontcolor=white:fontsize=42:x=(w-text_w)/2:y=300,drawtext=fontfile=${WEATHER_FONT}:text='ТЕХНИЧЕСКИЕ РАБОТЫ':fontcolor=0xffe65a:fontsize=54:x=(w-text_w)/2:y=365,drawtext=fontfile=${WEATHER_FONT}:text='ЭФИР СКОРО ВОЗОБНОВИТСЯ':fontcolor=white:fontsize=30:x=(w-text_w)/2:y=455,drawtext=fontfile=${WEATHER_FONT}:text='МУЛЬТИК ТВ  |  ВМЕСТЕ ИНТЕРЕСНЕЕ':fontcolor=0xe5ffef:fontsize=22:x=(w-text_w)/2:y=535" \
    -t 12 -map 0:v:0 -map 1:a:0 -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1200k -maxrate 1200k -bufsize 2400k \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -f flv rtmp://127.0.0.1/live/multiktv
}

play_channel_ident() {
  echo "В эфире: фирменная заставка МУЛЬТИК ТВ с оригинальной музыкальной темой."
  ffmpeg -hide_banner -nostdin -loglevel warning -re -t 6.5 \
    -f lavfi -i "color=c=0x24164f:s=1280x720:r=25:d=6.5" \
    -f lavfi -i 'aevalsrc=0.13*(if(between(t\,0\,0.42)\,sin(2*PI*523.25*t)\,0)+if(between(t\,0.42\,0.84)\,sin(2*PI*659.25*t)\,0)+if(between(t\,0.84\,1.26)\,sin(2*PI*783.99*t)\,0)+if(between(t\,1.26\,1.68)\,sin(2*PI*1046.5*t)\,0)+if(between(t\,1.68\,2.1)\,sin(2*PI*880*t)\,0)+if(between(t\,2.1\,2.52)\,sin(2*PI*783.99*t)\,0)+if(between(t\,2.52\,2.94)\,sin(2*PI*659.25*t)\,0)+if(between(t\,2.94\,3.36)\,sin(2*PI*783.99*t)\,0)+if(between(t\,3.36\,4.2)\,sin(2*PI*1046.5*t)\,0)+if(between(t\,4.2\,5.1)\,sin(2*PI*783.99*t)\,0)+if(between(t\,5.1\,6.5)\,sin(2*PI*523.25*t)\,0))+0.035*sin(2*PI*261.63*t):s=44100:d=6.5' \
    -loop 1 -framerate 25 -i /usr/local/srs/brand.png \
    -filter_complex "[0:v]drawbox=x=(w-430)/2+sin(t*1.4)*42:y=42:w=430:h=5:color=0xff5f9e@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=54:w=430:h=5:color=0xffcf4b@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=66:w=430:h=5:color=0x66d5a7@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=78:w=430:h=5:color=0x53c8ee@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=90:w=430:h=5:color=0x9475e8@0.9:t=fill[bg];[2:v]scale=270:270,format=rgba,fade=t=in:st=0:d=0.6:alpha=1,fade=t=out:st=5.9:d=0.6:alpha=1[logo];[bg][logo]overlay=x=(W-w)/2:y=72+8*sin(t*2):shortest=1,drawtext=fontfile=${WEATHER_FONT}:text='МУЛЬТИК ТВ':fontcolor=white:fontsize=76:x=(w-text_w)/2:y=372:shadowcolor=black@0.5:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:text='ВМЕСТЕ ИНТЕРЕСНЕЕ':fontcolor=0xffe27d:fontsize=30:x=(w-text_w)/2:y=474,drawtext=fontfile=${WEATHER_FONT}:text='ТВОЙ МИР ИСТОРИЙ И ОТКРЫТИЙ':fontcolor=0xded7ff:fontsize=18:x=(w-text_w)/2:y=535[v];[1:a]afade=t=in:st=0:d=0.08,afade=t=out:st=5.9:d=0.6[a]" \
    -map "[v]" -map "[a]" -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1400k -maxrate 1400k -bufsize 2800k \
    -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest -f flv rtmp://127.0.0.1/live/multiktv
}

start_test_signal() {
  exec ffmpeg -hide_banner -nostdin -loglevel warning -re \
    -f lavfi -i "testsrc2=size=1280x720:rate=25" \
    -f lavfi -i "sine=frequency=440:sample_rate=44100" \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='MULTIK TV':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2-55,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='PROGRAM SOURCE UNAVAILABLE - TEST SIGNAL':fontcolor=yellow:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2+55" \
    -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1000k -maxrate 1000k -bufsize 2000k \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv
}

# Publish an honest startup health document. SRS failure exits the container so Render can restart it.
HEALTH_DIR="/usr/local/srs/objs/nginx/html"
mkdir -p "$HEALTH_DIR/broadcast"
write_health() {
  local state="$1" detail="$2" streaming="false"
  if [[ "$state" == "live" ]]; then streaming="true"; fi
  printf '{"service":"multik-tv","streaming":%s,"status":"%s","detail":"%s","updatedAt":"%s"}\n' "$streaming" "$state" "$detail" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HEALTH_DIR/broadcast/health.json.tmp"
  mv "$HEALTH_DIR/broadcast/health.json.tmp" "$HEALTH_DIR/broadcast/health.json"
}
write_health "starting" "SRS started; preparing programme output"
if [[ -n "$PROGRAM_VIDEO_URL" && "$PROGRAM_RIGHTS_CONFIRMED" == "true" ]]; then
  echo "Downloading externally licensed programme after explicit rights confirmation."
  curl -fL --retry 4 --retry-delay 3 --connect-timeout 20 --max-time 900 \
    -A "MultikTV/1.0 (open-license broadcast; attribution on channel site)" \
    "$PROGRAM_VIDEO_URL" -o "$PROGRAM_FILE" >"$DOWNLOAD_LOG" 2>&1 &
  DOWNLOAD_PID=$!
else
  echo "No external programme enabled. Only original channel-made programmes will be aired until rights are confirmed."
fi

# Publish the channel slate and ident, then a test signal until original shows are rendered.
# Start the real programme playlist immediately after SRS is ready.
# Do not publish a synthetic test signal or a long startup slate.

if [[ -n "$DOWNLOAD_PID" ]]; then
  while kill -0 "$SRS_PID" 2>/dev/null; do
    if [[ -s "$PROGRAM_FILE" ]] && ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
      if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
        echo "Externally licensed programme downloaded and validated."
        kill "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
        FFMPEG_PID=""
        break
      fi
      echo "Downloaded file did not pass media validation; using original channel-made programmes."
      rm -f "$PROGRAM_FILE"
      kill "$FFMPEG_PID" 2>/dev/null || true
      wait "$FFMPEG_PID" 2>/dev/null || true
      FFMPEG_PID=""
      break
    fi
    if ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
      echo "Programme download failed; using original channel-made programmes."
      cat "$DOWNLOAD_LOG" || true
      kill "$FFMPEG_PID" 2>/dev/null || true
      wait "$FFMPEG_PID" 2>/dev/null || true
      FFMPEG_PID=""
      break
    fi
    sleep 2
  done
fi



download_dialogue_cartoon() {
  local slug="$1" title="$2" source_url="$3" subtitle_url="$4" credit="$5" russian_audio_url="$6"
  local raw="${ORIGINAL_DIR}/${slug}.source"
  local srt="${ORIGINAL_DIR}/${slug}.ru.srt"
  local vtt="${CAPTION_DIR}/${slug}.ru.vtt"
  local dub="${ORIGINAL_DIR}/${slug}.ru-audio"
  local output="${ORIGINAL_DIR}/00-dialogue-${slug}.mp4"

  if [[ -s "$output" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null 2>&1; then
    echo "Уже подготовлен выпуск: $title"
    return 0
  fi

  mkdir -p "$ORIGINAL_DIR" "$CAPTION_DIR"
  echo "Загружаю открытый мультфильм: $title"
  if ! curl -fL --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 1200 \
      -A "MultikTV/1.0 (open-license broadcast)" "$source_url" -o "$raw"; then
    echo "Не удалось скачать $title; пропускаю выпуск."
    rm -f "$raw"
    return 1
  fi
  if ! curl -fL --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 120 \
      -A "MultikTV/1.0 (open-license broadcast)" "$subtitle_url" -o "$srt"; then
    echo "Русские субтитры не получены; фильм останется без встроенных надписей."
    rm -f "$srt"
  elif ffmpeg -hide_banner -nostdin -loglevel error -y -i "$srt" "$vtt"; then
    echo "Русские субтитры подготовлены отдельным файлом: $vtt"
  else
    echo "Не удалось преобразовать субтитры в WebVTT; продолжаю без них."
    rm -f "$vtt"
  fi

  if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$raw" >/dev/null 2>&1; then
    echo "Файл $title не прошёл проверку; пропускаю."
    rm -f "$raw" "$srt" "$vtt"
    return 1
  fi

  local audio_input="$raw"
  local audio_map="0:a:0?"
  if [[ -n "$russian_audio_url" ]]; then
    echo "Найдена заявленная русская аудиодорожка для $title; проверяю источник."
    if curl -fL --retry 3 --connect-timeout 20 --max-time 900 "$russian_audio_url" -o "$dub" &&
       ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$dub" >/dev/null 2>&1; then
      audio_input="$dub"
      audio_map="1:a:0"
    else
      echo "Русская аудиодорожка не прошла проверку; оставляю оригинальную звуковую дорожку."
      rm -f "$dub"
    fi
  fi

  if [[ "$audio_input" == "$raw" ]]; then
    if ffmpeg -hide_banner -nostdin -loglevel warning -y -i "$raw" \
        -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,drawtext=fontfile=$WEATHER_FONT:text='$credit':fontcolor=white:fontsize=14:box=1:boxcolor=black@0.55:boxborderw=6:x=12:y=h-th-10" \
        -map 0:v:0 -map "$audio_map" -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p \
        -c:a aac -b:a 112k -ar 44100 -ac 2 -movflags +faststart "$output"; then
      echo "Готово: $title (оригинальная звуковая дорожка; субтитры не встроены)."
    else
      echo "Не удалось подготовить видео $title; пропускаю выпуск."
      rm -f "$raw" "$srt" "$output"
      return 1
    fi
  else
    if ffmpeg -hide_banner -nostdin -loglevel warning -y -i "$raw" -i "$dub" \
        -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,drawtext=fontfile=$WEATHER_FONT:text='$credit':fontcolor=white:fontsize=14:box=1:boxcolor=black@0.55:boxborderw=6:x=12:y=h-th-10" \
        -map 0:v:0 -map 1:a:0 -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"; then
      echo "Готово: $title (русская аудиодорожка; субтитры доступны отдельно)."
    else
      echo "Не удалось собрать русскую звуковую версию $title; пропускаю выпуск."
      rm -f "$raw" "$srt" "$dub" "$output"
      return 1
    fi
  fi

  rm -f "$raw" "$srt" "$dub"
}

prepare_dialogue_cartoon_library() {
  mkdir -p "$ORIGINAL_DIR" "$CAPTION_DIR"
  download_dialogue_cartoon "elephants-dream" "Слоновья мечта" \
    "https://commons.wikimedia.org/wiki/Special:Redirect/file/Elephants_Dream.ogv" \
    "https://commons.wikimedia.org/w/index.php?title=TimedText:Elephants_Dream.ogv.ru.srt&action=raw" \
    "(c) 2006 Blender Foundation / Netherlands Media Art Institute / elephantsdream.org | CC BY 2.5" \
    "${RUSSIAN_DUB_ELEPHANTS_DREAM_URL:-}" || true
  download_dialogue_cartoon "sintel" "Синтель" \
    "https://commons.wikimedia.org/wiki/Special:Redirect/file/Sintel_movie_-_Blender_Fondation.ogv" \
    "https://commons.wikimedia.org/w/index.php?title=TimedText:Sintel_movie_-_Blender_Fondation.ogv.ru.srt&action=raw" \
    "(c) Blender Foundation | sintel.org | CC BY 3.0" \
    "${RUSSIAN_DUB_SINTEL_URL:-}" || true
}

generate_weather_show() {
  local entry city lat lon url json txt clip temp feels wind humidity rain low high code condition
  local count=0
  local concat_file="${WEATHER_DIR}/concat.txt"
  rm -rf "$WEATHER_DIR"
  mkdir -p "$WEATHER_DIR"
  : > "$concat_file"

  local -a cities=(
    "Барнаул|53.35|83.76"
    "Москва|55.75|37.62"
    "Санкт-Петербург|59.94|30.31"
    "Новосибирск|55.03|82.92"
    "Екатеринбург|56.84|60.61"
    "Казань|55.80|49.11"
    "Красноярск|56.01|92.87"
    "Владивосток|43.12|131.89"
  )

  for entry in "${cities[@]}"; do
    sleep 2
    IFS='|' read -r city lat lon <<< "$entry"
    json="${WEATHER_DIR}/weather-${count}.json"
    txt="${WEATHER_DIR}/weather-${count}.txt"
    clip="${WEATHER_DIR}/weather-${count}.mp4"
    url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=temperature_2m_min,temperature_2m_max,precipitation_probability_max&forecast_days=1&timezone=auto"

    if ! curl -fsSL --retry 4 --retry-delay 5 --connect-timeout 10 --max-time 35 "$url" -o "$json"; then
      echo "Погода для ${city} временно недоступна; пропускаю город."
      continue
    fi

    temp="$(jq -r '.current.temperature_2m // empty' "$json")"
    feels="$(jq -r '.current.apparent_temperature // empty' "$json")"
    wind="$(jq -r '.current.wind_speed_10m // empty' "$json")"
    humidity="$(jq -r '.current.relative_humidity_2m // empty' "$json")"
    code="$(jq -r '.current.weather_code // -1' "$json")"
    rain="$(jq -r '.daily.precipitation_probability_max[0] // 0' "$json")"
    low="$(jq -r '.daily.temperature_2m_min[0] // empty' "$json")"
    high="$(jq -r '.daily.temperature_2m_max[0] // empty' "$json")"

    [[ -n "$temp" && -n "$feels" && -n "$wind" && -n "$humidity" ]] || {
      echo "Неполные погодные данные для ${city}; пропускаю город."
      continue
    }

    case "$code" in
      0) condition="Ясно" ;;
      1) condition="Преимущественно ясно" ;;
      2) condition="Переменная облачность" ;;
      3) condition="Пасмурно" ;;
      45|48) condition="Туман" ;;
      51|53|55|56|57) condition="Морось" ;;
      61|63|65|66|67) condition="Дождь" ;;
      71|73|75|77|85|86) condition="Снег" ;;
      80|81|82) condition="Кратковременный дождь" ;;
      95|96|99) condition="Гроза" ;;
      *) condition="Переменная погода" ;;
    esac

    {
      printf 'МУЛЬТИК ТВ  |  ПОГОДА С МУЛЬТИКОМ\n'
      printf '%s\n' "$city"
      printf 'Сейчас: %s °C  |  %s\n' "$temp" "$condition"
      printf 'Ощущается как: %s °C\n' "$feels"
      printf 'Ветер: %s км/ч  |  Влажность: %s%%\n' "$wind" "$humidity"
      printf 'Осадки: %s%%  |  Сегодня: %s...%s °C\n' "$rain" "$low" "$high"
      printf 'Данные: Open-Meteo  |  Обновлено: %s\n' "$(date '+%H:%M %Z')"
    } > "$txt"

    if ffmpeg -hide_banner -nostdin -loglevel error \
      -f lavfi -i "color=c=0x14558B:s=1280x720:r=25:d=12" \
      -vf "drawtext=fontfile=${WEATHER_FONT}:textfile=${txt}:fontcolor=white:fontsize=42:line_spacing=22:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=0x071B3C@0.68:boxborderw=34" \
      -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 -movflags +faststart "$clip"; then
      printf "file '%s'\n" "$clip" >> "$concat_file"
      count=$((count + 1))
    else
      echo "Не удалось создать погодный экран для ${city}."
    fi
  done

  (( count > 0 )) || {
    echo "Не удалось получить ни одного погодного прогноза."
    return 1
  }

  ffmpeg -hide_banner -nostdin -loglevel error -f concat -safe 0 -i "$concat_file" \
    -c copy -movflags +faststart "$WEATHER_VIDEO"
  echo "Погодная передача создана: ${count} городов, примерно $((count * 12)) секунд."
}

play_weather_show() {
  echo "В эфире: Погода с Мультиком."
  if ! generate_weather_show; then
    echo "Погодный выпуск пропущен; продолжаю основную программу."
    return 1
  fi
  play_channel_ident || echo "WARNING: channel ident failed; continuing to weather show."
  ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$WEATHER_VIDEO" \
    -an -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 \
    -b:v 1200k -maxrate 1200k -bufsize 2400k -f flv rtmp://127.0.0.1/live/multiktv
}

# External film downloads are opt-in. Wikimedia currently rate-limits this host (HTTP 429),
# so do not block the channel's own programme schedule on third-party downloads.
if [[ "${ENABLE_EXTERNAL_CARTOONS:-false}" == "true" ]]; then
  prepare_dialogue_cartoon_library
else
  echo "External cartoon downloads are disabled; using the six original channel-made programmes."
fi

if compgen -G "$ORIGINAL_DIR/*.mp4" >/dev/null; then
  echo "Готовые авторские передачи найдены в образе сервера; пропускаю долгую генерацию при запуске."
elif bash /usr/local/srs/generate-original-programs.sh "$ORIGINAL_DIR" "$WEATHER_FONT"; then
  echo "Авторские познавательные передачи подготовлены."
else
  echo "Не удалось создать авторские передачи; проверяю доступные оригинальные выпуски."
fi

# One FFmpeg publisher handles the entire playlist, avoiding RTMP disconnects between programmes.
PROGRAM_READY=0
if [[ -s "$PROGRAM_FILE" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
  PROGRAM_READY=1
fi
PLAYLIST_FILE="/tmp/multik-tv-broadcast.concat"
: > "$PLAYLIST_FILE"
if (( PROGRAM_READY )); then
  printf "file '%s'\n" "$PROGRAM_FILE" >> "$PLAYLIST_FILE"
fi
ORIGINAL_COUNT=0
for original_show in "$ORIGINAL_DIR"/*.mp4; do
  [[ -f "$original_show" ]] || continue
  if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$original_show" >/dev/null 2>&1; then
    printf "file '%s'\n" "$original_show" >> "$PLAYLIST_FILE"
    ORIGINAL_COUNT=$((ORIGINAL_COUNT + 1))
  else
    echo "ОШИБКА: повреждённый выпуск пропущен: ${original_show##*/}"
  fi
done
if (( PROGRAM_READY || ORIGINAL_COUNT > 0 )); then
  echo "Starting continuous broadcast playlist: licensed_items=$PROGRAM_READY, original_items=$ORIGINAL_COUNT."
  echo "Собираю единый MP4-файл, чтобы FFmpeg не перезапускал RTMP при переходе между выпусками."
  COMBINED_FILE="/tmp/multik-tv-continuous.mp4"
  rm -f "$COMBINED_FILE"
  if ! ffmpeg -hide_banner -nostdin -loglevel warning -y \
      -f concat -safe 0 -i "$PLAYLIST_FILE" \
      -map 0:v:0 -map 0:a:0? -c copy -movflags +faststart "$COMBINED_FILE"; then
    echo "Потоковое объединение без перекодирования не удалось; выполняю совместимую сборку."
    rm -f "$COMBINED_FILE"
    ffmpeg -hide_banner -nostdin -loglevel warning -y \
      -f concat -safe 0 -i "$PLAYLIST_FILE" \
      -map 0:v:0 -map 0:a:0? -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
      -c:a aac -b:a 96k -ar 44100 -ac 2 -movflags +faststart "$COMBINED_FILE"
  fi
  if [[ ! -s "$COMBINED_FILE" ]] || ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$COMBINED_FILE" >/dev/null 2>&1; then
    write_health "error" "Could not build a continuous programme file"
    echo "ОШИБКА: не удалось собрать единый файл для вещания."
    exit 1
  fi
  echo "Единый файл готов; запускаю один циклический MP4-поток."
  restart_delay=2
  while kill -0 "$SRS_PID" 2>/dev/null; do
    write_health "starting" "Starting continuous MP4 publisher"
    result=0
    ffmpeg -hide_banner -nostdin -loglevel info -report -re -stream_loop -1 -i "$COMBINED_FILE" \
      -map 0:v:0 -map 0:a:0? \
      -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,fps=20" \
      -c:v libx264 -preset ultrafast -tune zerolatency -threads 1 -pix_fmt yuv420p -r 20 -g 40 \
      -b:v 450k -maxrate 450k -bufsize 900k \
      -c:a aac -b:a 96k -ar 44100 -ac 2 \
      -f flv rtmp://127.0.0.1/live/multiktv &
    FFMPEG_PID=$!

    manifest_url="http://127.0.0.1:${HTTP_PORT}/live/multiktv.m3u8"
    manifest_file="/tmp/multik-tv-live-check.m3u8"
    live_confirmed=0
    for attempt in $(seq 1 45); do
      if ! kill -0 "$SRS_PID" 2>/dev/null; then
        echo "CRITICAL: SRS exited while waiting for HLS; requesting platform restart."
        kill "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
        FFMPEG_PID=""
        exit 1
      fi
      if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then break; fi
      if curl -fsS --connect-timeout 2 --max-time 4 "$manifest_url" -o "$manifest_file"; then
        # The newest HLS entry may still be open while SRS writes it.
        # Probe recent entries from newest to oldest and accept the first finalized segment.
        while IFS= read -r segment; do
          # Normalize HLS playlist line endings and whitespace before parsing the URI.
          segment="${segment//
          [[ -n "$segment_path" && "$segment_path" == *.ts ]] || continue
          # Keep SRS HLS context query parameters (for example hls_ctx) when fetching.
          case "$segment" in
            http://*|https://*) segment_url="$segment" ;;
            /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
            live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
            *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
          esac
          segment_probe="$(curl -sS --connect-timeout 2 --max-time 4 -o /dev/null -w '%{http_code} %{size_download}' "$segment_url" 2>&1 || true)"
          segment_http="${segment_probe%% *}"
          segment_size="${segment_probe#* }"
          echo "WATCHDOG: startup segment probe path=$segment_path result=$segment_probe"
          if [[ "$segment_http" == "200" && "$segment_size" =~ ^[0-9]+$ ]] && (( segment_size >= 188 )); then
            write_health "live" "HLS manifest and a finalized media segment are reachable"
            echo "LIVE: HLS manifest and finalized media segment confirmed: $segment"
            live_confirmed=1
            break
          fi
        done < <(awk '!/^#/ && NF {a[++n]=$0} END {for(i=n;i>0;i--) print a[i]}' "$manifest_file" | head -n 5)
        (( live_confirmed )) && break
      fi
      sleep 2
    done

    if (( live_confirmed )); then
      restart_delay=2
      last_segment=""
      last_change=$SECONDS
      advancing_segments=0
      health_live=0
      echo "WATCHDOG: verifying consecutive HLS segment progress before declaring LIVE."
      while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        if ! kill -0 "$SRS_PID" 2>/dev/null; then
          echo "CRITICAL: SRS exited; stopping publisher and requesting platform restart."
          kill "$FFMPEG_PID" 2>/dev/null || true
          wait "$FFMPEG_PID" 2>/dev/null || true
          FFMPEG_PID=""
          exit 1
        fi
        if curl -fsS --connect-timeout 2 --max-time 4 "$manifest_url" -o "$manifest_file"; then
          segment="$(awk '!/^#/ && NF {last=$0} END {print last}' "$manifest_file")"
          segment="${segment//
          segment_path="${segment%%\?*}"
          if [[ -n "$segment_path" ]]; then
            # Keep the full URI query string: SRS may require hls_ctx to serve a segment.
            case "$segment" in
              http://*|https://*) segment_url="$segment" ;;
              /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
              live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
              *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
            esac
            segment_bytes="$(curl -fsS --connect-timeout 2 --max-time 4 "$segment_url" -o /dev/null -w '%{size_download}' 2>/dev/null || echo 0)"
            if [[ "$segment_bytes" =~ ^[0-9]+$ ]] && (( segment_bytes >= 188 )); then
              if [[ "$segment_path" != "$last_segment" ]]; then
                last_segment="$segment_path"
                last_change=$SECONDS
                advancing_segments=$((advancing_segments + 1))
                echo "WATCHDOG: confirmed advancing media segment $advancing_segments."
                if (( advancing_segments >= 2 && health_live == 0 )); then
                  write_health "live" "HLS playlist advanced through multiple downloadable media segments"
                  echo "LIVE: continuous HLS progress confirmed by multiple finalized segments."
                  health_live=1
                fi
              fi
            else
              echo "WATCHDOG: newest HLS media segment is not downloadable or is too small."
            fi
          fi
          if (( SECONDS - last_change >= 30 )); then
            echo "WATCHDOG: HLS segment stalled for 30 seconds (no new downloadable segment); restarting FFmpeg."
            result=124
            break
          fi
        elif (( SECONDS - last_change >= 30 )); then
          echo "WATCHDOG: HLS manifest unavailable for 30 seconds; restarting FFmpeg."
          result=125
          break
        fi
        sleep 5
      done
    else
      echo "WATCHDOG: HLS did not become playable within 90 seconds; restarting FFmpeg."
      result=126
    fi

    if kill -0 "$FFMPEG_PID" 2>/dev/null; then kill "$FFMPEG_PID" 2>/dev/null || true; fi
    wait_result=0
    wait "$FFMPEG_PID" || wait_result=$?
    if (( result == 0 )); then result=$wait_result; fi
    FFMPEG_PID=""
    echo "PUBLISHER_EXIT: code=$result; recent FFmpeg diagnostics follow."
    for ffmpeg_log in /usr/local/srs/ffmpeg-*.log; do
      [[ -f "$ffmpeg_log" ]] || continue
      tail -n 80 "$ffmpeg_log" || true
    done
    write_health "recovering" "Watchdog detected publisher or HLS failure; automatic restart scheduled"
    echo "WATCHDOG: publisher stopped (code $result); retrying in ${restart_delay}s."
    sleep "$restart_delay"
    if (( restart_delay < 30 )); then
      restart_delay=$((restart_delay * 2))
      (( restart_delay > 30 )) && restart_delay=30
    fi
  done
else
  write_health "error" "No valid programme files are available"
  echo "ОШИБКА: нет ни одного проверенного видео. Тестовый сигнал не запускается."
  while kill -0 "$SRS_PID" 2>/dev/null; do sleep 5; done
fi

wait "$SRS_PID"
\r'/}"
          segment="${segment#"${segment%%[![:space:]]*}"}"
          segment="${segment%"${segment##*[![:space:]]}"}"
          # Remove URI fragments for checks, but preserve query parameters for SRS hls_ctx.
          segment="${segment%%#*}"
          segment_path="${segment%%\?*}"
          [[ -n "$segment_path" && "$segment_path" == *.ts ]] || continue
          # Keep SRS HLS context query parameters (for example hls_ctx) when fetching.
          case "$segment" in
            http://*|https://*) segment_url="$segment" ;;
            /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
            live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
            *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
          esac
          segment_probe="$(curl -sS --connect-timeout 2 --max-time 4 -o /dev/null -w '%{http_code} %{size_download}' "$segment_url" 2>&1 || true)"
          segment_http="${segment_probe%% *}"
          segment_size="${segment_probe#* }"
          echo "WATCHDOG: startup segment probe path=$segment_path result=$segment_probe"
          if [[ "$segment_http" == "200" && "$segment_size" =~ ^[0-9]+$ ]] && (( segment_size >= 188 )); then
            write_health "live" "HLS manifest and a finalized media segment are reachable"
            echo "LIVE: HLS manifest and finalized media segment confirmed: $segment"
            live_confirmed=1
            break
          fi
        done < <(awk '!/^#/ && NF {a[++n]=$0} END {for(i=n;i>0;i--) print a[i]}' "$manifest_file" | head -n 5)
        (( live_confirmed )) && break
      fi
      sleep 2
    done

    if (( live_confirmed )); then
      restart_delay=2
      last_segment=""
      last_change=$SECONDS
      advancing_segments=0
      health_live=0
      echo "WATCHDOG: verifying consecutive HLS segment progress before declaring LIVE."
      while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        if ! kill -0 "$SRS_PID" 2>/dev/null; then
          echo "CRITICAL: SRS exited; stopping publisher and requesting platform restart."
          kill "$FFMPEG_PID" 2>/dev/null || true
          wait "$FFMPEG_PID" 2>/dev/null || true
          FFMPEG_PID=""
          exit 1
        fi
        if curl -fsS --connect-timeout 2 --max-time 4 "$manifest_url" -o "$manifest_file"; then
          segment="$(awk '!/^#/ && NF {last=$0} END {print last}' "$manifest_file")"
          segment="${segment%%#*}"
          segment_path="${segment%%\?*}"
          if [[ -n "$segment_path" ]]; then
            # Keep the full URI query string: SRS may require hls_ctx to serve a segment.
            case "$segment" in
              http://*|https://*) segment_url="$segment" ;;
              /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
              live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
              *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
            esac
            segment_bytes="$(curl -fsS --connect-timeout 2 --max-time 4 "$segment_url" -o /dev/null -w '%{size_download}' 2>/dev/null || echo 0)"
            if [[ "$segment_bytes" =~ ^[0-9]+$ ]] && (( segment_bytes >= 188 )); then
              if [[ "$segment_path" != "$last_segment" ]]; then
                last_segment="$segment_path"
                last_change=$SECONDS
                advancing_segments=$((advancing_segments + 1))
                echo "WATCHDOG: confirmed advancing media segment $advancing_segments."
                if (( advancing_segments >= 2 && health_live == 0 )); then
                  write_health "live" "HLS playlist advanced through multiple downloadable media segments"
                  echo "LIVE: continuous HLS progress confirmed by multiple finalized segments."
                  health_live=1
                fi
              fi
            else
              echo "WATCHDOG: newest HLS media segment is not downloadable or is too small."
            fi
          fi
          if (( SECONDS - last_change >= 30 )); then
            echo "WATCHDOG: HLS segment stalled for 30 seconds (no new downloadable segment); restarting FFmpeg."
            result=124
            break
          fi
        elif (( SECONDS - last_change >= 30 )); then
          echo "WATCHDOG: HLS manifest unavailable for 30 seconds; restarting FFmpeg."
          result=125
          break
        fi
        sleep 5
      done
    else
      echo "WATCHDOG: HLS did not become playable within 90 seconds; restarting FFmpeg."
      result=126
    fi

    if kill -0 "$FFMPEG_PID" 2>/dev/null; then kill "$FFMPEG_PID" 2>/dev/null || true; fi
    wait_result=0
    wait "$FFMPEG_PID" || wait_result=$?
    if (( result == 0 )); then result=$wait_result; fi
    FFMPEG_PID=""
    echo "PUBLISHER_EXIT: code=$result; recent FFmpeg diagnostics follow."
    for ffmpeg_log in /usr/local/srs/ffmpeg-*.log; do
      [[ -f "$ffmpeg_log" ]] || continue
      tail -n 80 "$ffmpeg_log" || true
    done
    write_health "recovering" "Watchdog detected publisher or HLS failure; automatic restart scheduled"
    echo "WATCHDOG: publisher stopped (code $result); retrying in ${restart_delay}s."
    sleep "$restart_delay"
    if (( restart_delay < 30 )); then
      restart_delay=$((restart_delay * 2))
      (( restart_delay > 30 )) && restart_delay=30
    fi
  done
else
  write_health "error" "No valid programme files are available"
  echo "ОШИБКА: нет ни одного проверенного видео. Тестовый сигнал не запускается."
  while kill -0 "$SRS_PID" 2>/dev/null; do sleep 5; done
fi

wait "$SRS_PID"
\r'/}"
          segment="${segment#"${segment%%[![:space:]]*}"}"
          segment="${segment%"${segment##*[![:space:]]}"}"
          segment="${segment%%#*}"
          segment_path="${segment%%\?*}"
          if [[ -n "$segment_path" ]]; then
            # Keep the full URI query string: SRS may require hls_ctx to serve a segment.
            case "$segment" in
              http://*|https://*) segment_url="$segment" ;;
              /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
              live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
              *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
            esac
            segment_bytes="$(curl -fsS --connect-timeout 2 --max-time 4 "$segment_url" -o /dev/null -w '%{size_download}' 2>/dev/null || echo 0)"
            if [[ "$segment_bytes" =~ ^[0-9]+$ ]] && (( segment_bytes >= 188 )); then
              if [[ "$segment_path" != "$last_segment" ]]; then
                last_segment="$segment_path"
                last_change=$SECONDS
                advancing_segments=$((advancing_segments + 1))
                echo "WATCHDOG: confirmed advancing media segment $advancing_segments."
                if (( advancing_segments >= 2 && health_live == 0 )); then
                  write_health "live" "HLS playlist advanced through multiple downloadable media segments"
                  echo "LIVE: continuous HLS progress confirmed by multiple finalized segments."
                  health_live=1
                fi
              fi
            else
              echo "WATCHDOG: newest HLS media segment is not downloadable or is too small."
            fi
          fi
          if (( SECONDS - last_change >= 30 )); then
            echo "WATCHDOG: HLS segment stalled for 30 seconds (no new downloadable segment); restarting FFmpeg."
            result=124
            break
          fi
        elif (( SECONDS - last_change >= 30 )); then
          echo "WATCHDOG: HLS manifest unavailable for 30 seconds; restarting FFmpeg."
          result=125
          break
        fi
        sleep 5
      done
    else
      echo "WATCHDOG: HLS did not become playable within 90 seconds; restarting FFmpeg."
      result=126
    fi

    if kill -0 "$FFMPEG_PID" 2>/dev/null; then kill "$FFMPEG_PID" 2>/dev/null || true; fi
    wait_result=0
    wait "$FFMPEG_PID" || wait_result=$?
    if (( result == 0 )); then result=$wait_result; fi
    FFMPEG_PID=""
    echo "PUBLISHER_EXIT: code=$result; recent FFmpeg diagnostics follow."
    for ffmpeg_log in /usr/local/srs/ffmpeg-*.log; do
      [[ -f "$ffmpeg_log" ]] || continue
      tail -n 80 "$ffmpeg_log" || true
    done
    write_health "recovering" "Watchdog detected publisher or HLS failure; automatic restart scheduled"
    echo "WATCHDOG: publisher stopped (code $result); retrying in ${restart_delay}s."
    sleep "$restart_delay"
    if (( restart_delay < 30 )); then
      restart_delay=$((restart_delay * 2))
      (( restart_delay > 30 )) && restart_delay=30
    fi
  done
else
  write_health "error" "No valid programme files are available"
  echo "ОШИБКА: нет ни одного проверенного видео. Тестовый сигнал не запускается."
  while kill -0 "$SRS_PID" 2>/dev/null; do sleep 5; done
fi

wait "$SRS_PID"
\r'/}"
          segment="${segment#"${segment%%[![:space:]]*}"}"
          segment="${segment%"${segment##*[![:space:]]}"}"
          # Remove URI fragments for checks, but preserve query parameters for SRS hls_ctx.
          segment="${segment%%#*}"
          segment_path="${segment%%\?*}"
          [[ -n "$segment_path" && "$segment_path" == *.ts ]] || continue
          # Keep SRS HLS context query parameters (for example hls_ctx) when fetching.
          case "$segment" in
            http://*|https://*) segment_url="$segment" ;;
            /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
            live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
            *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
          esac
          segment_probe="$(curl -sS --connect-timeout 2 --max-time 4 -o /dev/null -w '%{http_code} %{size_download}' "$segment_url" 2>&1 || true)"
          segment_http="${segment_probe%% *}"
          segment_size="${segment_probe#* }"
          echo "WATCHDOG: startup segment probe path=$segment_path result=$segment_probe"
          if [[ "$segment_http" == "200" && "$segment_size" =~ ^[0-9]+$ ]] && (( segment_size >= 188 )); then
            write_health "live" "HLS manifest and a finalized media segment are reachable"
            echo "LIVE: HLS manifest and finalized media segment confirmed: $segment"
            live_confirmed=1
            break
          fi
        done < <(awk '!/^#/ && NF {a[++n]=$0} END {for(i=n;i>0;i--) print a[i]}' "$manifest_file" | head -n 5)
        (( live_confirmed )) && break
      fi
      sleep 2
    done

    if (( live_confirmed )); then
      restart_delay=2
      last_segment=""
      last_change=$SECONDS
      advancing_segments=0
      health_live=0
      echo "WATCHDOG: verifying consecutive HLS segment progress before declaring LIVE."
      while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        if ! kill -0 "$SRS_PID" 2>/dev/null; then
          echo "CRITICAL: SRS exited; stopping publisher and requesting platform restart."
          kill "$FFMPEG_PID" 2>/dev/null || true
          wait "$FFMPEG_PID" 2>/dev/null || true
          FFMPEG_PID=""
          exit 1
        fi
        if curl -fsS --connect-timeout 2 --max-time 4 "$manifest_url" -o "$manifest_file"; then
          segment="$(awk '!/^#/ && NF {last=$0} END {print last}' "$manifest_file")"
          segment="${segment%%#*}"
          segment_path="${segment%%\?*}"
          if [[ -n "$segment_path" ]]; then
            # Keep the full URI query string: SRS may require hls_ctx to serve a segment.
            case "$segment" in
              http://*|https://*) segment_url="$segment" ;;
              /*) segment_url="http://127.0.0.1:${HTTP_PORT}${segment}" ;;
              live/*) segment_url="http://127.0.0.1:${HTTP_PORT}/${segment}" ;;
              *) segment_url="http://127.0.0.1:${HTTP_PORT}/live/${segment#./}" ;;
            esac
            segment_bytes="$(curl -fsS --connect-timeout 2 --max-time 4 "$segment_url" -o /dev/null -w '%{size_download}' 2>/dev/null || echo 0)"
            if [[ "$segment_bytes" =~ ^[0-9]+$ ]] && (( segment_bytes >= 188 )); then
              if [[ "$segment_path" != "$last_segment" ]]; then
                last_segment="$segment_path"
                last_change=$SECONDS
                advancing_segments=$((advancing_segments + 1))
                echo "WATCHDOG: confirmed advancing media segment $advancing_segments."
                if (( advancing_segments >= 2 && health_live == 0 )); then
                  write_health "live" "HLS playlist advanced through multiple downloadable media segments"
                  echo "LIVE: continuous HLS progress confirmed by multiple finalized segments."
                  health_live=1
                fi
              fi
            else
              echo "WATCHDOG: newest HLS media segment is not downloadable or is too small."
            fi
          fi
          if (( SECONDS - last_change >= 30 )); then
            echo "WATCHDOG: HLS segment stalled for 30 seconds (no new downloadable segment); restarting FFmpeg."
            result=124
            break
          fi
        elif (( SECONDS - last_change >= 30 )); then
          echo "WATCHDOG: HLS manifest unavailable for 30 seconds; restarting FFmpeg."
          result=125
          break
        fi
        sleep 5
      done
    else
      echo "WATCHDOG: HLS did not become playable within 90 seconds; restarting FFmpeg."
      result=126
    fi

    if kill -0 "$FFMPEG_PID" 2>/dev/null; then kill "$FFMPEG_PID" 2>/dev/null || true; fi
    wait_result=0
    wait "$FFMPEG_PID" || wait_result=$?
    if (( result == 0 )); then result=$wait_result; fi
    FFMPEG_PID=""
    echo "PUBLISHER_EXIT: code=$result; recent FFmpeg diagnostics follow."
    for ffmpeg_log in /usr/local/srs/ffmpeg-*.log; do
      [[ -f "$ffmpeg_log" ]] || continue
      tail -n 80 "$ffmpeg_log" || true
    done
    write_health "recovering" "Watchdog detected publisher or HLS failure; automatic restart scheduled"
    echo "WATCHDOG: publisher stopped (code $result); retrying in ${restart_delay}s."
    sleep "$restart_delay"
    if (( restart_delay < 30 )); then
      restart_delay=$((restart_delay * 2))
      (( restart_delay > 30 )) && restart_delay=30
    fi
  done
else
  write_health "error" "No valid programme files are available"
  echo "ОШИБКА: нет ни одного проверенного видео. Тестовый сигнал не запускается."
  while kill -0 "$SRS_PID" 2>/dev/null; do sleep 5; done
fi

wait "$SRS_PID"
