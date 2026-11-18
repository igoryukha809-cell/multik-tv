#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs
HTTP_PORT="${PORT:-10000}"
if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
  echo "Invalid PORT value: $HTTP_PORT" >&2
  exit 1
fi
sed -E "s/^([[:space:]]*listen[[:space:]]+)8080;/\\1${HTTP_PORT};/" conf/multik-tv.conf > conf/render.conf
./objs/srs -c conf/render.conf &
SRS_PID=$!
FFMPEG_PID=""
cleanup(){ [[ -z "$FFMPEG_PID" ]] || kill "$FFMPEG_PID" 2>/dev/null || true; kill "$SRS_PID" 2>/dev/null || true; wait || true; }
trap cleanup TERM INT
until (echo >/dev/tcp/127.0.0.1/1935) >/dev/null 2>&1; do
  kill -0 "$SRS_PID" 2>/dev/null || { echo "SRS failed to start"; exit 1; }
  sleep 2
done
echo "SRS ready on HTTP port $HTTP_PORT; starting clearly labelled technical test signal"
ffmpeg -hide_banner -nostdin -loglevel warning -re \
  -f lavfi -i "testsrc2=size=1280x720:rate=25" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100" \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='MULTIK TV':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2-55,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='TECHNICAL TEST SIGNAL - NOT A LIVE PROGRAM':fontcolor=yellow:fontsize=28:x=(w-text_w)/2:y=(h-text_h)/2+55" \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1200k -maxrate 1200k -bufsize 2400k \
  -c:a aac -b:a 96k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv &
FFMPEG_PID=$!
wait -n "$SRS_PID" "$FFMPEG_PID"
exit $?
