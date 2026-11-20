#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs

HTTP_PORT="${PORT:-10000}"
PROGRAM_VIDEO_URL="${PROGRAM_VIDEO_URL:-https://commons.wikimedia.org/wiki/Special:Redirect/file/Morevna_Project_-_Pepper%26Carrot_%28animated_comic%29_-_Episode_6_-_The_Potion_Contest_%28Russian_variant%29.webm}"
PROGRAM_FILE="/tmp/multik-tv-program.webm"
DOWNLOAD_LOG="/tmp/multik-tv-download.log"
WEATHER_TIME="${WEATHER_TIME:-10:00}"
export TZ="${BROADCAST_TZ:-Asia/Krasnoyarsk}"
WEATHER_DIR="/tmp/multik-tv-weather"
WEATHER_VIDEO="/tmp/multik-tv-weather-show.mp4"
ORIGINAL_DIR="/tmp/multik-tv-originals"
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

curl -fL --retry 4 --retry-delay 3 --connect-timeout 20 --max-time 900 \
  -A "MultikTV/1.0 (open-license broadcast; attribution on channel site)" \
  "$PROGRAM_VIDEO_URL" -o "$PROGRAM_FILE" >"$DOWNLOAD_LOG" 2>&1 &
DOWNLOAD_PID=$!

# Publish a moving test picture immediately; do not leave the HLS endpoint empty
# while the 122 MB openly licensed episode is being downloaded.
play_maintenance_slate
play_channel_ident
start_test_signal &
FFMPEG_PID=$!

while kill -0 "$SRS_PID" 2>/dev/null; do
  if [[ -s "$PROGRAM_FILE" ]] && ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
    if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
      echo "Open-license program downloaded and validated."
      kill "$FFMPEG_PID" 2>/dev/null || true
      wait "$FFMPEG_PID" 2>/dev/null || true
      FFMPEG_PID=""
      break
    fi
    echo "Downloaded file did not pass media validation; switching to original channel-made programmes."
    rm -f "$PROGRAM_FILE"
    kill "$FFMPEG_PID" 2>/dev/null || true
    wait "$FFMPEG_PID" 2>/dev/null || true
    FFMPEG_PID=""
    break
  fi
  if ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
    echo "Program download failed; switching to original channel-made programmes."
    cat "$DOWNLOAD_LOG" || true
    kill "$FFMPEG_PID" 2>/dev/null || true
    wait "$FFMPEG_PID" 2>/dev/null || true
    FFMPEG_PID=""
    break
  fi
  sleep 2
done


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
  play_channel_ident
  ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$WEATHER_VIDEO" \
    -an -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 \
    -b:v 1200k -maxrate 1200k -bufsize 2400k -f flv rtmp://127.0.0.1/live/multiktv
}

if bash /usr/local/srs/generate-original-programs.sh "$ORIGINAL_DIR" "$WEATHER_FONT"; then
  echo "Авторские познавательные передачи подготовлены."
else
  echo "Не удалось создать авторские передачи; продолжаю с проверенной лицензированной программой."
fi

PROGRAM_READY=0
if [[ -s "$PROGRAM_FILE" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
  PROGRAM_READY=1
fi

if (( PROGRAM_READY )) || compgen -G "$ORIGINAL_DIR/*.mp4" >/dev/null; then
  echo "Starting the scheduled broadcast loop."
  if (( PROGRAM_READY )); then
    echo "Licensed programme: Pepper & Carrot Episode 6 (CC BY-SA 4.0)."
  else
    echo "Licensed download unavailable; running original channel-made programmes."
  fi
  echo "Weather show: every day at ${WEATHER_TIME} (${TZ})."
  WEATHER_PLAYED_DATE=""
  while kill -0 "$SRS_PID" 2>/dev/null; do
    TODAY="$(date +%F)"
    NOW="$(date +%H:%M)"
    if [[ "$NOW" > "$WEATHER_TIME" || "$NOW" == "$WEATHER_TIME" ]]; then
      if [[ "$WEATHER_PLAYED_DATE" != "$TODAY" ]]; then
        if play_weather_show; then
          WEATHER_PLAYED_DATE="$TODAY"
        fi
      fi
    fi

    if (( PROGRAM_READY )); then
      play_channel_ident
      echo "В эфире: Пеппер и Кэррот, эпизод 6 (CC BY-SA 4.0)."
      ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$PROGRAM_FILE" \
        -map 0:v:0 -map 0:a:0? \
        -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Pepper and Carrot Ep. 6 | Morevna Project | David Revoy | Gregoire Lourme | CC BY-SA 4.0':fontcolor=white:fontsize=15:box=1:boxcolor=black@0.55:boxborderw=7:x=12:y=h-th-12" \
        -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1600k -maxrate 1600k -bufsize 3200k \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv || echo "Основной ролик завершился с ошибкой; повторю цикл."
    fi
    for original_show in "$ORIGINAL_DIR"/*.mp4; do
      [[ -f "$original_show" ]] || continue
      echo "В эфире авторская передача: ${original_show##*/}."
      play_channel_ident
      ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$original_show" \
        -map 0:v:0 -map 0:a:0? -c:v libx264 -preset veryfast -tune zerolatency \
        -pix_fmt yuv420p -r 25 -g 50 -b:v 1100k -maxrate 1100k -bufsize 2200k \
        -c:a aac -b:a 64k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv || echo "Авторский выпуск завершился с ошибкой; перехожу к следующему."
    done
    sleep 3
  done
else
  echo "Keeping the technical test signal as the only output."
  wait "$FFMPEG_PID" || true
fi

wait "$SRS_PID"
