#!/usr/bin/env bash
# Prove audio+video capture: a browser plays a 440Hz tone + animated canvas;
# PulseAudio null sink captures the audio, ffmpeg muxes it with x11grab video.
set -u
SECS="${1:-10}"
DISP=":100"; RES="1280x720"; OUT=/home/node/rec; mkdir -p "$OUT"
eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv) 2>/dev/null

pkill -f "Xvfb $DISP" 2>/dev/null; pkill chromium 2>/dev/null; sleep 1

# 1. PulseAudio (user mode) + a virtual null sink
export PULSE_RUNTIME_PATH=/home/node/.pulse-run
pulseaudio -k 2>/dev/null; sleep 1
pulseaudio --start --exit-idle-time=-1 --log-target=file:/tmp/pa.log 2>/dev/null
sleep 2
pactl unload-module module-null-sink 2>/dev/null
pactl load-module module-null-sink sink_name=rec sink_properties=device.description=rec >/dev/null 2>&1
pactl set-default-sink rec 2>/dev/null
echo "pulse sinks: $(pactl list short sinks 2>/dev/null | tr '\n' ' ')"

# 2. virtual display
Xvfb $DISP -screen 0 ${RES}x24 -ac +extension RANDR >/tmp/xvfb.log 2>&1 &
XVFB=$!; sleep 2

# 3. a page that plays a tone + animates (base64 data URL, no file/network needed)
HTML='<!doctype html><html><body style="margin:0;background:#012"><canvas id=c width=1280 height=720></canvas>
<script>
const x=c.getContext("2d");let t=0;
(function d(){t++;x.fillStyle="#012";x.fillRect(0,0,1280,720);
x.fillStyle="hsl("+(t%360)+",90%,55%)";x.beginPath();
x.arc(640+300*Math.cos(t/15),360+200*Math.sin(t/15),80,0,7);x.fill();
x.fillStyle="#fff";x.font="40px sans-serif";x.fillText("REC "+Math.floor(t/30)+"s  440Hz tone",60,80);
requestAnimationFrame(d)})();
const a=new(window.AudioContext||webkitAudioContext)();const o=a.createOscillator();
o.frequency.value=440;const g=a.createGain();g.gain.value=0.3;o.connect(g);g.connect(a.destination);o.start();
</script></body></html>'
DATAURL="data:text/html;base64,$(printf '%s' "$HTML" | base64 -w0)"
PULSE_SINK=rec DISPLAY=$DISP chromium --no-sandbox --disable-gpu --no-first-run \
  --disable-dev-shm-usage --autoplay-policy=no-user-gesture-required \
  --window-position=0,0 --window-size=1280,720 --start-fullscreen \
  "$DATAURL" >/tmp/chromium.log 2>&1 &
CH=$!; sleep 5

# 4. record VIDEO (x11grab) + AUDIO (pulse monitor of the null sink) into one mp4
ffmpeg -y -f x11grab -draw_mouse 0 -video_size $RES -framerate 15 -i $DISP \
  -f pulse -i rec.monitor \
  -t $SECS -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 128k "$OUT/av.mp4" >/tmp/ffmpeg.log 2>&1
RC=$?

kill $CH $XVFB 2>/dev/null; pkill -f "Xvfb $DISP" 2>/dev/null
echo "ffmpeg_rc=$RC"; ls -la "$OUT/av.mp4"
echo "--- ffprobe (expect a video AND an audio stream) ---"
ffprobe -v error -show_entries stream=codec_type,codec_name,channels:format=duration -of default=noprint_wrappers=1 "$OUT/av.mp4" 2>&1
echo "--- mean audio volume (silence == -91dB) ---"
ffmpeg -i "$OUT/av.mp4" -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"
