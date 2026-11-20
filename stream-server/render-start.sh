#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs

HTTP_PORT="${PORT:-10000}"
PROGRAM_VIDEO_URL="${PROGRAM_VIDEO_URL:-https://commons.wikimedia.org/wiki/Special:Redirect/file/Morevna_Project_-_Pepper%26Carrot_%28animated_comic%29_-_Episode_6_-_The_Potion_Contest_%28Russian_variant%29.webm}"
PROGRAM_FILE="/tmp/multik-tv-program.webm"

if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
  echo "Invalid PORT value: $HTTP_PORT" >&2
  exit 1
fi

sed -E "s/^([[:space:]]*listen[[:space:]]+)8080;/\\1${HTTP_PORT};/" conf/multik-tv.conf > conf/render.conf
./objs/srs -c conf/render.conf &
SRS_PID=$!
FFMPEG_PID=""

cleanup() {
  [[ -z "$FFMPEG_PID" ]] || kill "$FFMPEG_PID" 2>/dev/null || true
  kill "$SRS_PID" 2>/dev/null || true
  wait || true
}
trap cleanup TERM INT

until (echo >/dev/tcp/127.0.0.1/1935) >/dev/null 2>&1; do
  kill -0 "$SRS_PID" 2>/dev/null || { echo "SRS failed to start"; exit 1; }
  sleep 2
done

echo "SRS ready on HTTP port $HTTP_PORT."
echo "Downloading the openly licensed Russian animation from Wikimedia Commons."
if curl -fL --retry 4 --retry-delay 3 --connect-timeout 20 --max-time 900 \
  -A "MultikTV/1.0 (open-license broadcast; attribution on channel site)" \
  "$PROGRAM_VIDEO_URL" -o "$PROGRAM_FILE" && [[ -s "$PROGRAM_FILE" ]]; then
  echo "Program file downloaded: $(du -h "$PROGRAM_FILE" | cut -f1)"
  echo "Starting the licensed program loop."
  while kill -0 "$SRS_PID" 2>/dev/null; do
    ffmpeg -hide_banner -nostdin -loglevel warning -re -stream_loop -1 -i "$PROGRAM_FILE" \
      -map 0:v:0 -map 0:a:0? \
      -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Pepper and Carrot Ep. 6 | Morevna Project | David Revoy | Gregoire Lourme | CC BY-SA 4.0':fontcolor=white:fontsize=15:box=1:boxcolor=black@0.55:boxborderw=7:x=12:y=h-th-12" \
      -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1600k -maxrate 1600k -bufsize 3200k \
      -c:a aac -b:a 128k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv || true
    echo "Program playback ended or source disconnected; retrying in 10 seconds."
    sleep 10
  done
else
  echo "Program download failed. Falling back to a clearly labelled technical test signal."
  while kill -0 "$SRS_PID" 2>/dev/null; do
    ffmpeg -hide_banner -nostdin -loglevel warning -re \
      -f lavfi -i "testsrc2=size=1280x720:rate=25" \
      -f lavfi -i "sine=frequency=440:sample_rate=44100" \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='MULTIK TV':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2-55,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='PROGRAM SOURCE UNAVAILABLE - TEST SIGNAL':fontcolor=yellow:fontsize=25:x=(w-text_w)/2:y=(h-text_h)/2+55" \
      -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1000k -maxrate 1000k -bufsize 2000k \
      -c:a aac -b:a 96k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv || true
    sleep 5
  done
fi

wait "$SRS_PID"
