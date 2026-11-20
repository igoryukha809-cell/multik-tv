#!/usr/bin/env bash
set -Eeuo pipefail
cd /usr/local/srs

HTTP_PORT="${PORT:-10000}"
PROGRAM_VIDEO_URL="${PROGRAM_VIDEO_URL:-https://commons.wikimedia.org/wiki/Special:Redirect/file/Morevna_Project_-_Pepper%26Carrot_%28animated_comic%29_-_Episode_6_-_The_Potion_Contest_%28Russian_variant%29.webm}"
PROGRAM_FILE="/tmp/multik-tv-program.webm"
DOWNLOAD_LOG="/tmp/multik-tv-download.log"

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

start_test_signal() {
  ffmpeg -hide_banner -nostdin -loglevel warning -re \
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
    echo "Downloaded file did not pass media validation; retaining test signal."
    rm -f "$PROGRAM_FILE"
    break
  fi
  if ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
    echo "Program download failed; retaining the clearly labelled test signal."
    cat "$DOWNLOAD_LOG" || true
    wait "$FFMPEG_PID" || true
    FFMPEG_PID=""
    exit 0
  fi
  sleep 2
done

if [[ -s "$PROGRAM_FILE" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROGRAM_FILE" >/dev/null 2>&1; then
  echo "Starting the licensed program loop."
  echo "License: CC BY-SA 4.0; attribution is burned into the video."
  while kill -0 "$SRS_PID" 2>/dev/null; do
    ffmpeg -hide_banner -nostdin -loglevel warning -re -stream_loop -1 -i "$PROGRAM_FILE" \
      -map 0:v:0 -map 0:a:0? \
      -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Pepper and Carrot Ep. 6 | Morevna Project | David Revoy | Gregoire Lourme | CC BY-SA 4.0':fontcolor=white:fontsize=15:box=1:boxcolor=black@0.55:boxborderw=7:x=12:y=h-th-12" \
      -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -r 25 -g 50 -b:v 1600k -maxrate 1600k -bufsize 3200k \
      -c:a aac -b:a 128k -ar 44100 -ac 2 -f flv rtmp://127.0.0.1/live/multiktv
    echo "Program encoder stopped; restarting the encoder in 5 seconds."
    sleep 5
  done
else
  echo "Keeping the technical test signal as the only output."
  wait "$FFMPEG_PID" || true
fi

wait "$SRS_PID"
