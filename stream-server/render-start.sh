#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs

HTTP_PORT="${PORT:-10000}"
PROGRAM_VIDEO_URL="${PROGRAM_VIDEO_URL:-}"
PROGRAM_RIGHTS_CONFIRMED="${PROGRAM_RIGHTS_CONFIRMED:-false}"
PROGRAM_FILE="/tmp/multik-tv-program.webm"
DOWNLOAD_LOG="/tmp/multik-tv-download.log"
WEATHER_TIME="${WEATHER_TIME:-07:30}"
export TZ="${BROADCAST_TZ:-Europe/Moscow}"
if [[ ! "$WEATHER_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "Invalid WEATHER_TIME (expected HH:MM): $WEATHER_TIME" >&2
  exit 1
fi
WEATHER_DIR="/tmp/multik-tv-weather"
WEATHER_VIDEO="/tmp/multik-tv-weather-show.mp4"
BIRTHDAY_VIDEO="/tmp/multik-tv-channel-birthday.mp4"
CHANNEL_IDENT_VIDEO="/tmp/multik-tv-channel-ident.mp4"
ORIGINAL_DIR="/usr/local/srs/originals"
CAPTION_DIR="/usr/local/srs/objs/nginx/html/captions"
WEATHER_FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
  echo "Invalid PORT value: $HTTP_PORT" >&2
  exit 1
fi

sed -E "s/^([[:space:]]*listen[[:space:]]+)8080;/\\1${HTTP_PORT};/" conf/multik-tv.conf > conf/render.conf

# Render currently checks the HLS URL as its service health endpoint. Create an
# empty, valid live playlist before SRS starts so startup is not marked failed
# while the first real media segments are being generated. SRS replaces it
# with the real playlist as soon as publishing begins.
HEALTH_DIR="/usr/local/srs/objs/nginx/html"
mkdir -p "$HEALTH_DIR/live" "$HEALTH_DIR/broadcast"
printf '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:0\n' > "$HEALTH_DIR/live/multiktv.m3u8"

./objs/srs -c conf/render.conf &
SRS_PID=$!
FFMPEG_PID=""
DOWNLOAD_PID=""
scheduled_weather_date=""

cleanup() {
  [[ -z "$FFMPEG_PID" ]] || kill "$FFMPEG_PID" 2>/dev/null || true
  [[ -z "$DOWNLOAD_PID" ]] || kill "$DOWNLOAD_PID" 2>/dev/null || true
  kill "$SRS_PID" 2>/dev/null || true
  # Let the main loop reap children and inspect their exit status.
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
    -f lavfi -i "aevalsrc=0.10*sin(2*PI*523.25*t)+0.08*sin(2*PI*659.25*t)+0.06*sin(2*PI*783.99*t):s=44100:d=6.5" \
    -loop 1 -framerate 25 -i /usr/local/srs/brand.png \
    -filter_complex "[0:v]drawbox=x=(w-430)/2+sin(t*1.4)*42:y=42:w=430:h=5:color=0xff5f9e@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=54:w=430:h=5:color=0xffcf4b@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=66:w=430:h=5:color=0x66d5a7@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=78:w=430:h=5:color=0x53c8ee@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=90:w=430:h=5:color=0x9475e8@0.9:t=fill[bg];[2:v]scale=270:270,format=rgba,fade=t=in:st=0:d=0.6:alpha=1,fade=t=out:st=5.9:d=0.6:alpha=1[logo];[bg][logo]overlay=x=(W-w)/2:y=72+8*sin(t*2):shortest=1,drawtext=fontfile=${WEATHER_FONT}:text='МУЛЬТИК ТВ':fontcolor=white:fontsize=76:x=(w-text_w)/2:y=372:shadowcolor=black@0.5:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:text='ВМЕСТЕ ИНТЕРЕСНЕЕ':fontcolor=0xffe27d:fontsize=30:x=(w-text_w)/2:y=474,drawtext=fontfile=${WEATHER_FONT}:text='ТВОЙ МИР ИСТОРИЙ И ОТКРЫТИЙ':fontcolor=0xded7ff:fontsize=18:x=(w-text_w)/2:y=535[v];[1:a]afade=t=in:st=0:d=0.08,afade=t=out:st=5.9:d=0.6[a]" \
    -map "[v]" -map "[a]" -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1400k -maxrate 1400k -bufsize 2800k \
    -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest -f flv rtmp://127.0.0.1/live/multiktv
}


make_channel_ident_video() {
  echo "Создаю короткую фирменную межпрограммную заставку для вставки между передачами."
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 6.5 \
    -f lavfi -i "color=c=0x24164f:s=1280x720:r=25:d=6.5" \
    -f lavfi -i "aevalsrc=0.10*sin(2*PI*523.25*t)+0.08*sin(2*PI*659.25*t)+0.06*sin(2*PI*783.99*t):s=44100:d=6.5" \
    -loop 1 -framerate 25 -i /usr/local/srs/brand.png \
    -filter_complex "[0:v]drawbox=x=(w-430)/2+sin(t*1.4)*42:y=42:w=430:h=5:color=0xff5f9e@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=54:w=430:h=5:color=0xffcf4b@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=66:w=430:h=5:color=0x66d5a7@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=78:w=430:h=5:color=0x53c8ee@0.9:t=fill,drawbox=x=(w-430)/2+sin(t*1.4)*42:y=90:w=430:h=5:color=0x9475e8@0.9:t=fill[bg];[2:v]scale=270:270,format=rgba,fade=t=in:st=0:d=0.6:alpha=1,fade=t=out:st=5.9:d=0.6:alpha=1[logo];[bg][logo]overlay=x=(W-w)/2:y=72+8*sin(t*2):shortest=1,drawtext=fontfile=${WEATHER_FONT}:text='МУЛЬТИК ТВ':fontcolor=white:fontsize=76:x=(w-text_w)/2:y=372:shadowcolor=black@0.5:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:text='ВМЕСТЕ ИНТЕРЕСНЕЕ':fontcolor=0xffe27d:fontsize=30:x=(w-text_w)/2:y=474,drawtext=fontfile=${WEATHER_FONT}:text='ТВОЙ МИР ИСТОРИЙ И ОТКРЫТИЙ':fontcolor=0xded7ff:fontsize=18:x=(w-text_w)/2:y=535[v];[1:a]afade=t=in:st=0:d=0.08,afade=t=out:st=5.9:d=0.6[a]" \
    -map "[v]" -map "[a]" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest -movflags +faststart "$CHANNEL_IDENT_VIDEO"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$CHANNEL_IDENT_VIDEO" >/dev/null
}

make_launch_countdown() {
  local output="/tmp/multik-tv-launch-countdown.mp4"
  echo "Создаю пятиминутный эфирный отсчёт до начала первой программы."
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 300 \
    -f lavfi -i "color=c=0x183b70:s=1280x720:r=25:d=300" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawbox=x=0:y=0:w=1280:h=16:color=0xffd35c:t=fill,drawbox=x=0:y=704:w=1280:h=16:color=0x62d6df:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='ВЕЩАНИЕ НАЧНЁТСЯ ЧЕРЕЗ':fontcolor=white:fontsize=42:x=(w-text_w)/2:y=190,drawtext=fontfile=${WEATHER_FONT}:text='МУЛЬТИК ТВ':fontcolor=0xffdf79:fontsize=64:x=(w-text_w)/2:y=285,drawtext=fontfile=${WEATHER_FONT}:text='%{eif\\:floor((300-t)/60)\\:d\\:2}\\:%{eif\\:mod(ceil(300-t)\\,60)\\:d\\:2}':fontcolor=white:fontsize=112:borderw=3:bordercolor=0x102044:x=(w-text_w)/2:y=405,drawtext=fontfile=${WEATHER_FONT}:text='ПРИЯТНОГО ПРОСМОТРА!':fontcolor=0xbdeeff:fontsize=26:x=(w-text_w)/2:y=570" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null
}

make_channel_opening() {
  local output="/tmp/multik-tv-opening.mp4"
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 8 \
    -f lavfi -i "color=c=0x183b70:s=1280x720:r=25:d=8" \
    -f lavfi -i "aevalsrc=0.10*sin(2*PI*523.25*t)+0.07*sin(2*PI*659.25*t)+0.05*sin(2*PI*783.99*t):s=44100:d=8" \
    -vf "drawbox=x=0:y=0:w=1280:h=16:color=0xffd35c:t=fill,drawbox=x=0:y=704:w=1280:h=16:color=0x62d6df:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='ДОБРО ПОЖАЛОВАТЬ!':fontcolor=0xffdf79:fontsize=48:x=(w-text_w)/2:y=175,drawtext=fontfile=${WEATHER_FONT}:text='ВРЕМЯ УЗНАВАТЬ НОВОЕ И МЕЧТАТЬ':fontcolor=white:fontsize=34:x=(w-text_w)/2:y=270,drawtext=fontfile=${WEATHER_FONT}:text='НАШ ДЕТСКИЙ ТЕЛЕКАНАЛ':fontcolor=0xbdeeff:fontsize=25:x=(w-text_w)/2:y=385" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null
}

make_programme_intro() {
  local title="$1" output="$2" title_file="$3"
  printf '%s\n' "$title" > "$title_file"
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 4 \
    -f lavfi -i "color=c=0x263c72:s=1280x720:r=25:d=4" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawbox=x=0:y=0:w=1280:h=12:color=0xffd35c:t=fill,drawbox=x=0:y=708:w=1280:h=12:color=0x62d6df:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='СЕЙЧАС В ЭФИРЕ':fontcolor=0xffdf79:fontsize=42:x=(w-text_w)/2:y=185,drawtext=fontfile=${WEATHER_FONT}:textfile=${title_file}:fontcolor=white:fontsize=48:borderw=2:bordercolor=0x13264b:x=(w-text_w)/2:y=300,drawtext=fontfile=${WEATHER_FONT}:text='ПРИЯТНОГО ПРОСМОТРА!':fontcolor=0xbdeeff:fontsize=24:x=(w-text_w)/2:y=435" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null
}

make_channel_promo() {
  local output="/tmp/multik-tv-channel-promo.mp4"
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 6 \
    -f lavfi -i "color=c=0x244c73:s=1280x720:r=25:d=6" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawbox=x=0:y=0:w=1280:h=14:color=0xffd35c:t=fill,drawbox=x=0:y=706:w=1280:h=14:color=0x62d6df:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='ВПЕРЁД К ОТКРЫТИЯМ!':fontcolor=0xffdf79:fontsize=48:x=(w-text_w)/2:y=200,drawtext=fontfile=${WEATHER_FONT}:text='ПОЗНАВАТЕЛЬНЫЕ ИСТОРИИ':fontcolor=white:fontsize=34:x=(w-text_w)/2:y=305,drawtext=fontfile=${WEATHER_FONT}:text='ПРИРОДА  •  КОСМОС  •  НАУКА':fontcolor=0xbdeeff:fontsize=28:x=(w-text_w)/2:y=410" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null
}

make_next_program_card() {
  local output="$1" schedule_file="$2"
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 8 \
    -f lavfi -i "color=c=0x182d58:s=1280x720:r=25:d=8" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -vf "drawbox=x=0:y=0:w=1280:h=14:color=0xffc94f:t=fill,drawbox=x=0:y=706:w=1280:h=14:color=0x56c9dc:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='СКОРО В ЭФИРЕ':fontcolor=0xffd76a:fontsize=48:borderw=2:bordercolor=0x102044:x=(w-text_w)/2:y=95,drawtext=fontfile=${WEATHER_FONT}:textfile=${schedule_file}:fontcolor=white:fontsize=36:line_spacing=24:borderw=2:bordercolor=0x102044:x=(w-text_w)/2:y=220:shadowcolor=black@0.5:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:text='ПРОГРАММА ПО ПОРЯДКУ ЭФИРНОГО ПЛЕЙЛИСТА':fontcolor=0xbfeeff:fontsize=21:x=(w-text_w)/2:y=600" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$output"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$output" >/dev/null
}

make_channel_birthday_bumper() {
  local title_file="/tmp/channel-birthday-title.txt" sub_file="/tmp/channel-birthday-sub.txt"
  printf '%s\n' 'С ДНЁМ РОЖДЕНИЯ, НАШ КАНАЛ!' > "$title_file"
  printf '%s\n' '17 НОЯБРЯ — ДЕНЬ НАШЕЙ ИСТОРИИ' 'СПАСИБО, ЧТО ВЫ С НАМИ!' > "$sub_file"
  echo "Создаю 12-секундную праздничную заставку для общего видеосигнала."
  ffmpeg -hide_banner -nostdin -loglevel warning -y -t 12 \
    -f lavfi -i "color=c=0x542c91:s=1280x720:r=25:d=12" \
    -f lavfi -i 'aevalsrc=0.12*(if(between(t\,0\,0.45)\,sin(2*PI*523.25*t)\,0)+if(between(t\,0.45\,0.9)\,sin(2*PI*659.25*t)\,0)+if(between(t\,0.9\,1.35)\,sin(2*PI*783.99*t)\,0)+if(between(t\,1.35\,1.8)\,sin(2*PI*1046.5*t)\,0)+if(between(t\,1.8\,2.25)\,sin(2*PI*880*t)\,0)+if(between(t\,2.25\,2.7)\,sin(2*PI*783.99*t)\,0)+if(between(t\,2.7\,3.15)\,sin(2*PI*659.25*t)\,0)+if(between(t\,3.15\,3.6)\,sin(2*PI*783.99*t)\,0)+if(between(t\,3.6\,4.5)\,sin(2*PI*1046.5*t)\,0)+if(between(t\,4.5\,5.4)\,sin(2*PI*783.99*t)\,0)+if(between(t\,5.4\,12)\,sin(2*PI*523.25*t)*exp(-(t-5.4)*0.18)\,0)):s=44100:d=12' \
    -loop 1 -framerate 25 -i /usr/local/srs/brand.png \
    -filter_complex "[0:v]drawbox=x='80+35*sin(t*1.3)':y=45:w=1120:h=8:color=0xffd45e@0.95:t=fill,drawbox=x='100+65*cos(t*1.1)':y=650:w=1080:h=7:color=0xff8fcf@0.9:t=fill,drawbox=x='120+mod(t*90\,1000)':y='120+35*sin(t*2)':w=18:h=18:color=0xffdf79@0.9:t=fill,drawbox=x='1000-mod(t*75\,900)':y='500-30*cos(t*2)':w=16:h=16:color=0xff9ccf@0.9:t=fill,drawtext=fontfile=${WEATHER_FONT}:textfile=${title_file}:fontcolor=white:fontsize=58:borderw=3:bordercolor=0x36205f:x=(w-text_w)/2:y=350:shadowcolor=black@0.4:shadowx=3:shadowy=3,drawtext=fontfile=${WEATHER_FONT}:textfile=${sub_file}:fontcolor=0xffe7a0:fontsize=27:line_spacing=16:x=(w-text_w)/2:y=455:shadowcolor=black@0.4:shadowx=2:shadowy=2[bg];[2:v]scale=210:210,format=rgba,fade=t=in:st=0:d=0.8:alpha=1,fade=t=out:st=11:d=0.8:alpha=1[logo];[bg][logo]overlay=x=(W-w)/2:y=85+10*sin(t*2):shortest=1[v]" \
    -map "[v]" -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest "$BIRTHDAY_VIDEO"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$BIRTHDAY_VIDEO" >/dev/null
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
  local entry city city_say lat lon url json txt clip speech spoken temp feels wind humidity rain low high code condition source cache_file cache_source cache_time now temp_say wind_say feels_say
  local count=0
  local city_index=0
  local concat_file="${WEATHER_DIR}/concat.txt"
  local cache_dir="/tmp/multik-tv-weather-cache"
  rm -rf "$WEATHER_DIR"
  mkdir -p "$WEATHER_DIR" "$cache_dir"
  : > "$concat_file"

  local -a cities=(
    # Broadcast weather rotation: all 11 configured cities.
    "Норильск|Норильске|69.35|88.20"
    "Южно-Сахалинск|Южно-Сахалинске|46.96|142.73"
    "Иркутск|Иркутске|52.29|104.28"
    "Новосибирск|Новосибирске|55.03|82.92"
    "Санкт-Петербург|Санкт-Петербурге|59.94|30.31"
    "Москва|Москве|55.75|37.62"
    "Брянск|Брянске|53.24|34.36"
    "Хабаровск|Хабаровске|48.48|135.07"
    "Владивосток|Владивостоке|43.12|131.89"
    "Петропавловск-Камчатский|Петропавловске-Камчатском|53.04|158.65"
    "Омск|Омске|54.99|73.37"
  )

  for entry in "${cities[@]}"; do
    sleep 2
    IFS='|' read -r city city_say lat lon <<< "$entry"
    city_index=$((city_index + 1))
    json="${WEATHER_DIR}/weather-${count}.json"
    txt="${WEATHER_DIR}/weather-${count}.txt"
    clip="${WEATHER_DIR}/weather-${count}.mp4"
    cache_file="${cache_dir}/weather-${city_index}.json"
    cache_source="${cache_dir}/weather-${city_index}.source"
    cache_time="${cache_dir}/weather-${city_index}.timestamp"
    now="$(date +%s)"
    source=""

    # MET Norway asks clients outside the Nordic region not to repeat an
    # identical Locationforecast request more often than every 3 hours.
    if [[ -s "$cache_file" && -s "$cache_time" && -s "$cache_source" ]]; then
      cached_at="$(cat "$cache_time")"
      if [[ "$cached_at" =~ ^[0-9]+$ ]] && (( now - cached_at < 10800 )); then
        cp "$cache_file" "$json"
        source="$(cat "$cache_source")"
        echo "Использую кэш прогноза для ${city} из ${source}."
      fi
    fi

    if [[ -z "$source" ]]; then
      source="MET Norway (CC BY 4.0)"
      url="https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat}&lon=${lon}"
      weather_ua="${WEATHER_USER_AGENT:-MultikTV/1.0 (https://github.com/igoryukha809-cell/multik-tv)}"
      if curl -fsSL --retry 1 --retry-delay 3 --connect-timeout 8 --max-time 20 \
        -H "User-Agent: ${weather_ua}" -H "Accept: application/json" "$url" -o "$json"; then
        if [[ -s "$json" ]]; then
          cp "$json" "$cache_file"
          printf '%s' "$source" > "$cache_source"
          printf '%s' "$now" > "$cache_time"
        fi
      else
        echo "MET Norway недоступен для ${city}; переключаюсь на Open-Meteo."
        source="Open-Meteo"
        url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto"
        if ! curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 8 --max-time 25 \
          -H "Accept: application/json" "$url" -o "$json"; then
          echo "Open-Meteo недоступен для ${city}; переключаюсь на резервный wttr.in."
          source="wttr.in"
          url="https://wttr.in/${lat},${lon}?format=j1"
          if ! curl -fsSL --retry 1 --retry-delay 2 --connect-timeout 8 --max-time 20 \
            -H "User-Agent: MultikTV/1.0 (https://github.com/igoryukha809-cell/multik-tv)" "$url" -o "$json"; then
            echo "Все погодные источники недоступны для ${city}; добавляю карточку с сообщением о недоступности прогноза."
            source="Резервная заставка"
          fi
        fi
        if [[ -s "$json" ]]; then
          cp "$json" "$cache_file"
          printf '%s' "$source" > "$cache_source"
          printf '%s' "$now" > "$cache_time"
        fi
      fi
    fi

    if [[ "$source" == "Резервная заставка" ]]; then
      temp="—"; feels=""; wind="—"; humidity="—"; rain="—"; low="—"; high="—"
      condition="Прогноз временно недоступен"
    elif [[ "$source" == "wttr.in" ]]; then
      temp="$(jq -r '.current_condition[0].temp_C // empty' "$json")"
      feels="$(jq -r '.current_condition[0].FeelsLikeC // empty' "$json")"
      wind="$(jq -r '.current_condition[0].windspeedKmph // empty' "$json")"
      humidity="$(jq -r '.current_condition[0].humidity // empty' "$json")"
      condition="$(jq -r '.current_condition[0].weatherDesc[0].value // "Условия уточняются"' "$json")"
      rain="$(jq -r '.weather[0].hourly[0].chanceofrain // "—"' "$json")"
      low="$(jq -r '.weather[0].mintempC // "—"' "$json")"
      high="$(jq -r '.weather[0].maxtempC // "—"' "$json")"
    elif [[ "$source" == "Open-Meteo" ]]; then
      temp="$(jq -r '.current.temperature_2m // empty' "$json")"
      feels="$(jq -r '.current.apparent_temperature // empty' "$json")"
      wind="$(jq -r '.current.wind_speed_10m // empty' "$json")"
      humidity="$(jq -r '.current.relative_humidity_2m // empty' "$json")"
      rain="$(jq -r '.daily.precipitation_probability_max[0] // "—"' "$json")"
      low="$(jq -r '.daily.temperature_2m_min[0] // "—"' "$json")"
      high="$(jq -r '.daily.temperature_2m_max[0] // "—"' "$json")"
      code="$(jq -r '.current.weather_code // empty' "$json")"
      case "$code" in
        0) condition="Ясно" ;;
        1) condition="Преимущественно ясно" ;;
        2) condition="Переменная облачность" ;;
        3) condition="Облачно" ;;
        45|48) condition="Туман" ;;
        51|53|55|56|57) condition="Морось" ;;
        61|63|65|66|67|80|81|82) condition="Дождь" ;;
        71|73|75|77|85|86) condition="Снег" ;;
        95|96|99) condition="Гроза" ;;
        *) condition="Условия уточняются" ;;
      esac
    else
      temp="$(jq -r '.properties.timeseries[0].data.instant.details.air_temperature // empty' "$json")"
      feels="$(jq -r '.properties.timeseries[0].data.instant.details.apparent_air_temperature // empty' "$json")"
      wind="$(jq -r '.properties.timeseries[0].data.instant.details.wind_speed // empty' "$json")"
      humidity="$(jq -r '.properties.timeseries[0].data.instant.details.relative_humidity // empty' "$json")"
      code="$(jq -r '.properties.timeseries[0].data.next_1_hours.summary.symbol_code // .properties.timeseries[0].data.next_6_hours.summary.symbol_code // empty' "$json")"
      rain="—"; low="—"; high="—"
      case "$code" in
        *clearsky*) condition="Ясно" ;;
        *fair*) condition="Преимущественно ясно" ;;
        *partlycloudy*) condition="Переменная облачность" ;;
        *cloudy*) condition="Облачно" ;;
        *fog*) condition="Туман" ;;
        *lightrain*|*rain*) condition="Дождь" ;;
        *sleet*) condition="Мокрый снег" ;;
        *snow*) condition="Снег" ;;
        *thunder*) condition="Гроза" ;;
        *) condition="Условия уточняются" ;;
      esac
    fi

    if [[ "$source" != "Резервная заставка" ]] && [[ -z "$temp" || -z "$wind" || -z "$humidity" ]]; then
      echo "Неполные погодные данные от ${source} для ${city}; добавляю резервную карточку."
      source="Резервная заставка"
      temp="—"; feels=""; wind="—"; humidity="—"; rain="—"; low="—"; high="—"
      condition="Прогноз временно недоступен"
    fi

    # Keep one presenter team for the entire daily episode; rotate between days.
    presenter_day="$(TZ=Europe/Moscow date +%j)"
    presenter_slot=$(( (10#$presenter_day - 1) % 4 ))
    case "$presenter_slot" in
      0) presenter="Лисёнок Рыжик и Облачко Капелька"; presenter_hello="Привет, друзья! Это Рыжик и Капелька!" ;;
      1) presenter="Пингвинёнок Пик и Снежинка Искорка"; presenter_hello="Здравствуйте! С вами Пик и Искорка!" ;;
      2) presenter="Совёнок Умка и Солнышко Лучик"; presenter_hello="Привет! На связи Умка и Лучик!" ;;
      *) presenter="Медвежонок Топа и Радужка"; presenter_hello="Добрый день! Это Топа и Радужка!" ;;
    esac

    {
      printf 'ПОГОДА | ПРОГНОЗ ДЛЯ ВСЕЙ СЕМЬИ\\n'
      printf 'ВЕДУЩИЕ: %s\\n' "$presenter"
      printf 'ГОРОД %s ИЗ 11\\n' "$city_index"
      printf '%s\\n' "$city"
      printf 'СЕЙЧАС: %s °C | %s\\n' "$temp" "$condition"
      [[ -z "$feels" ]] || printf 'ОЩУЩАЕТСЯ КАК: %s °C\\n' "$feels"
      printf 'ВЕТЕР: %s км/ч | ВЛАЖНОСТЬ: %s проц.\\n' "$wind" "$humidity"
      [[ "$rain" == "—" ]] || printf 'ВЕРОЯТНОСТЬ ОСАДКОВ: %s проц.\\n' "$rain"
      [[ "$low" == "—" || "$high" == "—" ]] || printf 'ДНЁМ: %s...%s °C\\n' "$low" "$high"
      printf 'ИСТОЧНИК: %s | %s\\n' "$source" "$(TZ=Europe/Moscow date '+%H:%M МСК')"
    } > "$txt"
    # The unavailable forecast still gets a visible card and an honest voice-over.
    if [[ "$source" == "Резервная заставка" ]]; then
      spoken="${presenter_hello} Сейчас мы расскажем о погоде в ${city_say}. К сожалению, прогноз временно недоступен. Мы обязательно вернёмся к прогнозу позже!"
    else
      temp_say="$(printf '%.0f' "$temp" 2>/dev/null || printf '%s' "$temp")"
      wind_say="$(printf '%.0f' "$wind" 2>/dev/null || printf '%s' "$wind")"
      feels_say=""
      if [[ -n "$feels" ]]; then
        feels_say=" По ощущениям ${feels} градусов."
      fi
      if (( city_index == 1 )); then
        spoken="${presenter_hello} Сегодня мы отправимся в путешествие по городам России! Начинаем с ${city_say}. Сейчас ${temp_say} градусов. ${condition}!${feels_say} Ветер ${wind_say} километров в час. Влажность воздуха ${humidity} процентов."
      else
        spoken="А теперь заглянем в ${city_say}. Здесь сейчас ${temp_say} градусов. ${condition}!${feels_say} Ветер ${wind_say} километров в час. Влажность воздуха ${humidity} процентов."
      fi
      if [[ "$rain" != "—" ]]; then
        spoken+=" Вероятность осадков ${rain} процентов."
      fi
      case "$condition" in
        *Снег*) spoken+=" Одевайтесь теплее и выбирайте удобную обувь." ;;
        *Дождь*|*Морось*) spoken+=" Не забудьте зонт и будьте внимательны на мокрой дороге." ;;
        *Гроза*) spoken+=" Во время грозы лучше оставаться в помещении." ;;
        *Туман*) spoken+=" На улице будьте особенно внимательны." ;;
        *) spoken+=" Выбирайте одежду по погоде и хорошего вам дня!" ;;
      esac
      if (( city_index == ${#cities[@]} )); then
        spoken+=" На этом наш прогноз завершён. Спасибо, что были с нами! До новых встреч!"
      fi
    fi
    printf '%s\n' "$spoken" > "${WEATHER_DIR}/weather-${count}.speech.txt"
    speech="${WEATHER_DIR}/weather-${count}.wav"
    if ! espeak-ng -v ru+f3 -s 132 -p 82 -a 175 -g 7 -w "$speech" "$spoken" 2>/dev/null; then
      echo "Не удалось синтезировать голос ведущего для ${city}; использую резервную тишину."
      speech=""
    fi

    if [[ -n "$speech" ]]; then
      if ! ffmpeg -hide_banner -nostdin -loglevel error \
        -f lavfi -i "color=c=0x14558B:s=1280x720:r=25:d=40" -i "$speech" \
        -vf "drawtext=fontfile=${WEATHER_FONT}:textfile=${txt}:fontcolor=white:fontsize=42:line_spacing=22:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=0x071B3C@0.68:boxborderw=34" \
        -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
        -c:a aac -b:a 96k -ar 44100 -ac 2 -shortest -movflags +faststart "$clip"; then
        echo "Не удалось собрать погодный экран с голосом для ${city}; сохраняю город с экранной карточкой."
        speech=""
      fi
    fi
    if [[ -z "$speech" ]]; then
      if ! ffmpeg -hide_banner -nostdin -loglevel error \
        -f lavfi -i "color=c=0x14558B:s=1280x720:r=25:d=12" \
        -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
        -vf "drawtext=fontfile=${WEATHER_FONT}:textfile=${txt}:fontcolor=white:fontsize=42:line_spacing=22:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=0x071B3C@0.68:boxborderw=34" \
        -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
        -c:a aac -b:a 48k -ar 44100 -ac 2 -shortest -movflags +faststart "$clip"; then
        echo "Не удалось собрать даже экранную карточку погоды для ${city}."
        continue
      fi
    fi
      printf "file '%s'\n" "$clip" >> "$concat_file"
      count=$((count + 1))
  done

  if (( count == 0 )); then
    # Never invent forecast values. Preserve the scheduled slot with an honest fallback slate.
    echo "Прогнозы недоступны; создаю погодную заставку без выдуманных данных."
    clip="${WEATHER_DIR}/weather-unavailable.mp4"
    if ! ffmpeg -hide_banner -nostdin -loglevel error \
      -f lavfi -i "color=c=0x14558B:s=1280x720:r=25:d=12" \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
      -vf "drawtext=fontfile=${WEATHER_FONT}:text='ПОГОДА':fontcolor=white:fontsize=68:x=(w-text_w)/2:y=190,drawtext=fontfile=${WEATHER_FONT}:text='ДАННЫЕ ПРОГНОЗА ВРЕМЕННО НЕДОСТУПНЫ':fontcolor=0xffe27d:fontsize=34:x=(w-text_w)/2:y=310,drawtext=fontfile=${WEATHER_FONT}:text='Попробуем обновить их в следующем эфирном цикле':fontcolor=white:fontsize=25:x=(w-text_w)/2:y=390" \
      -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -r 25 -g 50 \
      -c:a aac -b:a 48k -ar 44100 -ac 2 -shortest -movflags +faststart "$clip"; then
      echo "Не удалось создать резервную погодную заставку."
      return 1
    fi
    printf "file '%s'\n" "$clip" >> "$concat_file"
    count=1
  fi

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
    -map 0:v:0 -map 0:a:0? \
    -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 \
    -b:v 1200k -maxrate 1200k -bufsize 2400k \
    -c:a aac -b:a 96k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv
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

# Build the forecast at the scheduled broadcast time, not at container startup.
# This avoids stale weather and keeps the main programme on air during data collection.
WEATHER_READY=1
echo "Ежедневный погодный выпуск запланирован на ${WEATHER_TIME} (Europe/Moscow); данные будут собраны перед выходом в эфир."

# One FFmpeg publisher handles the entire playlist, avoiding RTMP disconnects between programmes.
PROGRAM_READY=0
if [[ -s "$PROGRAM_FILE" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
  PROGRAM_READY=1
fi
PLAYLIST_FILE="/tmp/multik-tv-broadcast.concat"
: > "$PLAYLIST_FILE"
LOCAL_PROGRAM_DIR="${LOCAL_PROGRAM_DIR:-/usr/local/srs/programs}"
LOCAL_COUNT=0
mkdir -p "$LOCAL_PROGRAM_DIR"
declare -a PROGRAM_ITEMS=()
if (( PROGRAM_READY )); then
  PROGRAM_ITEMS+=("$PROGRAM_FILE")
fi
# Files placed in this channel-owned media folder are picked up automatically.
shopt -s nullglob nocaseglob
for local_show in "$LOCAL_PROGRAM_DIR"/*.mp4 "$LOCAL_PROGRAM_DIR"/*.m4v "$LOCAL_PROGRAM_DIR"/*.mov "$LOCAL_PROGRAM_DIR"/*.webm; do
  [[ -f "$local_show" ]] || continue
  if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$local_show" >/dev/null 2>&1; then
    PROGRAM_ITEMS+=("$local_show")
    LOCAL_COUNT=$((LOCAL_COUNT + 1))
    echo "Добавлена локальная программа: ${local_show##*/}"
  else
    echo "ОШИБКА: локальный файл не прошёл проверку и пропущен: ${local_show##*/}"
  fi
done
shopt -u nullglob nocaseglob
ORIGINAL_COUNT=0
for original_show in "$ORIGINAL_DIR"/*.mp4; do
  [[ -f "$original_show" ]] || continue
  if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$original_show" >/dev/null 2>&1; then
    PROGRAM_ITEMS+=("$original_show")
    ORIGINAL_COUNT=$((ORIGINAL_COUNT + 1))
  else
    echo "ОШИБКА: повреждённый выпуск пропущен: ${original_show##*/}"
  fi
done
# Build original station idents as independent media clips. They are inserted
# after each programme in the shared stream, not as browser overlays.
if (( PROGRAM_READY || LOCAL_COUNT > 0 || ORIGINAL_COUNT > 0 )); then
  echo "Starting continuous broadcast playlist: external_items=$PROGRAM_READY, local_items=$LOCAL_COUNT, original_items=$ORIGINAL_COUNT."
  make_channel_ident_video
  birthday_today=0
  if [[ "$(date '+%m-%d')" == "11-17" ]]; then
    make_channel_birthday_bumper
    birthday_today=1
  fi
  PLAY_FIRST_LAUNCH_COUNTDOWN=0
  FIRST_LAUNCH_MARKER="$HEALTH_DIR/.first-launch-countdown-played"
  if [[ ! -f "$FIRST_LAUNCH_MARKER" ]]; then
    PLAY_FIRST_LAUNCH_COUNTDOWN=1
    make_launch_countdown
    touch "$FIRST_LAUNCH_MARKER"
    echo "STARTUP: first-launch countdown generated locally."
  else
    echo "STARTUP: first-launch countdown was already played; skipping it."
  fi
  make_channel_opening
  make_channel_promo
  printf "file '%s'\\n" "/tmp/multik-tv-opening.mp4" >> "$PLAYLIST_FILE"
  printf "file '%s'\\n" "/tmp/multik-tv-channel-promo.mp4" >> "$PLAYLIST_FILE"
  item_index=0
  total_programmes=${#PROGRAM_ITEMS[@]}
  for programme in "${PROGRAM_ITEMS[@]}"; do
    item_index=$((item_index + 1))
    card_file="/tmp/multik-tv-upcoming-${item_index}.mp4"
    schedule_file="/tmp/multik-tv-upcoming-${item_index}.txt"
    : > "$schedule_file"
    # Show this programme plus the next three playlist entries. The list wraps
    # at the end because the broadcast playlist itself loops continuously.
    for offset in 0 1 2 3; do
      upcoming_index=$(( (item_index - 1 + offset) % total_programmes ))
      upcoming_path="${PROGRAM_ITEMS[$upcoming_index]}"
      display_name="${upcoming_path##*/}"
      display_name="${display_name%.*}"
      display_name="${display_name//_/ }"
      display_name="${display_name//-/ }"
      printf '%s. %s\\n' "$((offset + 1))" "$display_name" >> "$schedule_file"
    done
    echo "Готовлю эфирный список «Скоро в эфире» для программы №${item_index}."
    if make_next_program_card "$card_file" "$schedule_file"; then
      printf "file '%s'\\n" "$card_file" >> "$PLAYLIST_FILE"
    else
      echo "WARNING: не удалось собрать список будущих программ; продолжаю без него."
    fi
    programme_intro="/tmp/multik-tv-now-${item_index}.mp4"
    programme_title_file="/tmp/multik-tv-now-${item_index}.txt"
    if make_programme_intro "$display_name" "$programme_intro" "$programme_title_file"; then
      printf "file '%s'\\n" "$programme_intro" >> "$PLAYLIST_FILE"
    else
      echo "WARNING: не удалось собрать карточку текущей передачи."
    fi
    printf "file '%s'\\n" "$programme" >> "$PLAYLIST_FILE"
    if (( item_index % 2 == 0 )); then
      printf "file '%s'\\n" "/tmp/multik-tv-channel-promo.mp4" >> "$PLAYLIST_FILE"
    fi
    if (( birthday_today && item_index == 1 )); then
      printf "file '%s'\\n" "$BIRTHDAY_VIDEO" >> "$PLAYLIST_FILE"
      birthday_today=0
    fi
    # Keep a station ident at every programme boundary, including the loop boundary.
    printf "file '%s'\\n" "$CHANNEL_IDENT_VIDEO" >> "$PLAYLIST_FILE"
  done
  echo "Плашки «Далее в эфире» и фирменные перебивки включены в общий эфирный плейлист."
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
  if (( PLAY_FIRST_LAUNCH_COUNTDOWN )); then
    echo "STARTUP: показываю пятиминутный отсчёт первого запуска канала."
    if kill -0 "$SRS_PID" 2>/dev/null; then
      if ffmpeg -hide_banner -nostdin -loglevel warning -re -i "/tmp/multik-tv-launch-countdown.mp4" \
          -map 0:v:0 -map 0:a:0 \
          -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,fps=20" \
          -c:v libx264 -preset ultrafast -tune zerolatency -threads 1 -pix_fmt yuv420p -r 20 -g 40 \
          -b:v 450k -maxrate 450k -bufsize 900k \
          -c:a aac -b:a 96k -ar 44100 -ac 2 \
          -f flv rtmp://127.0.0.1/live/multiktv; then
        echo "STARTUP: пятиминутный отсчёт завершён; запускаю основную программу."
      else
        echo "WARNING: отсчёт завершился с ошибкой; перехожу к основному эфиру."
      fi
    fi
  else
    echo "STARTUP: пропускаю заставку — первый запуск уже отмечен в постоянной базе."
  fi
  restart_delay=2
  while kill -0 "$SRS_PID" 2>/dev/null; do
    write_health "starting" "Starting continuous MP4 publisher"
    scheduled_weather_date=""
    result=0
    ffmpeg -hide_banner -nostdin -loglevel info -report -re -stream_loop -1 -i "$COMBINED_FILE" \
      -map 0:v:0 -map 0:a:0? \
      -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,fps=20,drawbox=x=0:y=h-30:w=iw:h=30:color=0x14264dcc:t=fill,drawtext=fontfile=${WEATHER_FONT}:text='НАШ КАНАЛ':fontcolor=white@0.94:fontsize=15:box=1:boxcolor=0x14264dcc:boxborderw=7:x=w-tw-14:y=12,drawtext=fontfile=${WEATHER_FONT}:text='0+':fontcolor=white:fontsize=13:box=1:boxcolor=0x7132a8@0.95:boxborderw=5:x=12:y=12,drawtext=fontfile=${WEATHER_FONT}:text='АВТОРСКИЕ ПРОГРАММЫ  •  ПОГОДА  •  ВОПРОС ДНЯ  •  ПРИРОДА И КОСМОС':fontcolor=white:fontsize=12:x=12:y=h-th-9" \
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
          # SRS may append query parameters to segment URIs; strip them before extension/path checks.
          segment="$(printf '%s' "$segment" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
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
        # SRS can finish writing TS files before the playlist exposes their names.
        # Probe the newest local segments as a fallback instead of restarting a healthy publisher.
        if (( live_confirmed == 0 )); then
          while IFS= read -r segment_file; do
            [[ -n "$segment_file" ]] || continue
            segment="$segment_file"
            segment_path="/live/$segment"
            segment_url="http://127.0.0.1:${HTTP_PORT}${segment_path}"
            segment_probe="$(curl -sS --connect-timeout 2 --max-time 4 -o /dev/null -w '%{http_code} %{size_download}' "$segment_url" 2>&1 || true)"
            segment_http="${segment_probe%% *}"
            segment_size="${segment_probe#* }"
            echo "WATCHDOG: filesystem fallback probe file=$segment result=$segment_probe"
            if [[ "$segment_http" == "200" && "$segment_size" =~ ^[0-9]+$ ]] && (( segment_size >= 188 )); then
              write_health "live" "HLS media segment reachable through filesystem fallback"
              echo "LIVE: finalized HLS segment confirmed through filesystem fallback: $segment"
              live_confirmed=1
              break
            fi
          done < <(find "$HEALTH_DIR/live" -maxdepth 1 -type f -name 'multiktv-*.ts' -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -n 5 | cut -d' ' -f2-)
        fi
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
      # Daily weather slot is scheduled by Moscow wall-clock time. If the
      # service starts after today's slot, wait until tomorrow rather than
      # unexpectedly airing the forecast immediately.
      if [[ "$(date '+%H:%M')" < "$WEATHER_TIME" ]]; then
        LAST_WEATHER_DATE="$(date -d yesterday +%F)"
      else
        LAST_WEATHER_DATE="$(date +%F)"
      fi
      while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        current_date="$(date +%F)"
        current_clock="$(date '+%H:%M')"
        if (( WEATHER_READY )) && [[ "$current_date" != "$LAST_WEATHER_DATE" && ( "$current_clock" == "$WEATHER_TIME" || "$current_clock" > "$WEATHER_TIME" ) ]]; then
          echo "SCHEDULE: Moscow time $WEATHER_TIME reached; preparing today's weather while the main programme remains on air."
          if generate_weather_show && [[ -s "$WEATHER_VIDEO" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$WEATHER_VIDEO" >/dev/null 2>&1; then
            result=127
            scheduled_weather_date="$current_date"
            echo "SCHEDULE: today's forecast is ready; switching to the weather programme."
            kill "$FFMPEG_PID" 2>/dev/null || true
            break
          else
            echo "WARNING: today's weather could not be prepared; keeping the main programme on air and skipping this slot."
            LAST_WEATHER_DATE="$current_date"
          fi
        fi
        if ! kill -0 "$SRS_PID" 2>/dev/null; then
          echo "CRITICAL: SRS exited; stopping publisher and requesting platform restart."
          kill "$FFMPEG_PID" 2>/dev/null || true
          wait "$FFMPEG_PID" 2>/dev/null || true
          FFMPEG_PID=""
          exit 1
        fi
        if curl -fsS --connect-timeout 2 --max-time 4 "$manifest_url" -o "$manifest_file"; then
          segment="$(awk '!/^#/ && NF {last=$0} END {print last}' "$manifest_file")"
          segment="$(printf '%s' "$segment" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          segment="${segment%%#*}"
          segment_path="${segment%%\\?*}"
          if [[ -z "$segment_path" ]]; then
            # The HLS manifest may lag the segment writer; inspect finalized local TS files.
            segment="$(find "$HEALTH_DIR/live" -maxdepth 1 -type f -name 'multiktv-*.ts' -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
            if [[ -n "$segment" ]]; then
              segment_path="/live/$segment"
              echo "WATCHDOG: filesystem fallback progress check: $segment"
            else
              segment_path=""
            fi
          fi
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
                write_health "live" "HLS media segment is advancing"
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
    wait "$FFMPEG_PID" 2>/dev/null || wait_result=$?
    if (( result == 0 )); then result=$wait_result; fi
    FFMPEG_PID=""
    if (( result == 127 )) && [[ -n "${scheduled_weather_date:-}" ]]; then
      echo "SCHEDULE: airing weather programme for ${scheduled_weather_date:-unknown} (Europe/Moscow)."
      write_health "starting" "Switching to the scheduled daily weather programme"
      play_channel_ident || echo "WARNING: channel ident failed before scheduled weather."
      if ! ffmpeg -hide_banner -nostdin -loglevel warning -re -i "$WEATHER_VIDEO" \
          -map 0:v:0 -map 0:a:0? \
          -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,fps=20" \
          -c:v libx264 -preset ultrafast -tune zerolatency -threads 1 -pix_fmt yuv420p -r 20 -g 40 \
          -b:v 450k -maxrate 450k -bufsize 900k \
          -c:a aac -b:a 96k -ar 44100 -ac 2 \
          -f flv rtmp://127.0.0.1/live/multiktv; then
        echo "WARNING: scheduled weather playback failed; returning to the main programme."
      fi
      LAST_WEATHER_DATE="${scheduled_weather_date:-$LAST_WEATHER_DATE}"
      write_health "recovering" "Scheduled weather programme finished; resuming the continuous programme"
      continue
    fi
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

if wait "$SRS_PID" 2>/dev/null; then
  :
else
  srs_exit_code=$?
  echo "CRITICAL: SRS process ended (wait status $srs_exit_code); requesting platform restart."
  exit 1
fi