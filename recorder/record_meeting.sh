#!/usr/bin/env bash
# Minimal native meeting recorder for an Agent37 instance (no Docker).
# Browser joins a Jitsi room on a private Xvfb display; ffmpeg captures it.
set -u
ROOM="${1:-agent37rectest$RANDOM}"
SECS="${2:-20}"
HOST="${3:-meet.ffmuc.net}"
DISP=":100"
RES="1280x720"
OUT=/home/node/rec
mkdir -p "$OUT"

pkill -f "Xvfb $DISP" 2>/dev/null; pkill -f "chromium" 2>/dev/null; sleep 1

# 1. private virtual display (separate from the agent's :99)
Xvfb $DISP -screen 0 ${RES}x24 -ac +extension RANDR >/tmp/xvfb.log 2>&1 &
XVFB=$!; sleep 2

# 2. browser joins the room with synthetic camera+mic (fake media devices)
URL="https://${HOST}/${ROOM}#config.prejoinConfig.enabled=false&config.prejoinPageEnabled=false&userInfo.displayName=Agent37Recorder&config.startWithVideoMuted=false&config.startWithAudioMuted=false"
DISPLAY=$DISP chromium \
  --no-sandbox --disable-gpu --no-first-run --disable-dev-shm-usage \
  --use-fake-ui-for-media-stream --use-fake-device-for-media-stream \
  --autoplay-policy=no-user-gesture-required \
  --window-position=0,0 --window-size=1280,720 --start-fullscreen \
  "$URL" >/tmp/chromium.log 2>&1 &
CH=$!
sleep 22   # let it load + join

DISPLAY=$DISP import -window root "$OUT/before.png" 2>/dev/null

# 3. record the display to mp4
ffmpeg -y -f x11grab -draw_mouse 0 -video_size $RES -framerate 15 -i $DISP \
  -t $SECS -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  "$OUT/meeting.mp4" >/tmp/ffmpeg.log 2>&1
RC=$?

DISPLAY=$DISP import -window root "$OUT/after.png" 2>/dev/null

# 4. teardown
kill $CH $XVFB 2>/dev/null; pkill -f "Xvfb $DISP" 2>/dev/null

# 5. report
echo "room=$ROOM  ffmpeg_rc=$RC"
ls -la "$OUT"/meeting.mp4 "$OUT"/before.png "$OUT"/after.png 2>/dev/null
echo "--- ffprobe ---"
ffprobe -v error -show_entries format=duration,size:stream=codec_type,codec_name,width,height \
  -of default=noprint_wrappers=1 "$OUT/meeting.mp4" 2>&1
echo "--- chromium tail ---"; tail -4 /tmp/chromium.log
echo "--- ffmpeg tail ---"; tail -3 /tmp/ffmpeg.log
