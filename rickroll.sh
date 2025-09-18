#!/bin/bash
# Rick Astley in your Terminal — loops video + sound, cleans safely, timeout-friendly.
# Original by Serene & Justine Tunney <3 — loop/cleanup hardening by ChatGPT
version='1.4'
rick='https://keroserene.net/lol'
video="$rick/astley80.full.bz2"
audio_raw="$rick/roll.s16"

NEVER_GONNA='curl -s -L http://bit.ly/10hA8iC | bash'
MAKE_YOU_CRY="$HOME/.bashrc"

red='\x1b[38;5;9m'
yell='\x1b[38;5;216m'
green='\x1b[38;5;10m'
purp='\x1b[38;5;171m'

echo -en '\x1b[s'  # Save cursor.

has?() { hash "$1" 2>/dev/null; }

usage () {
  echo -en "${green}Rick Astley performs ♪ Never Gonna Give You Up ♪ on STDOUT."
  echo -e "  ${purp}[v$version]"
  echo -e "${yell}Usage: ./astley.sh [OPTIONS...]"
  echo -e "${purp}OPTIONS : ${yell}"
  echo -e " help   - Show this message."
  echo -e " inject - Append to ${purp}${USER}${yell}'s bashrc. (Recommended :D)"
}

for arg in "$@"; do
  if [[ "$arg" == "help"* || "$arg" == "-h"* || "$arg" == "--h"* ]]; then
    usage && exit
  elif [[ "$arg" == "inject" ]]; then
    echo -en "${red}[Inject] "
    echo "$NEVER_GONNA" >> "$MAKE_YOU_CRY"
    echo -e "${green}Appended to $MAKE_YOU_CRY. <3"
    echo -en "${yell}If you've astley overdosed, "
    echo -e "delete the line ${purp}\"$NEVER_GONNA\"${yell}."
    exit
  else
    echo -e "${red}Unrecognized option: \"$arg\""
    usage && exit
  fi
done

# ---------- Private cache dir ----------
CACHE_DIR=$(mktemp -d /tmp/rickroll.XXXXXX)
VIDEO_CACHE="$CACHE_DIR/astley80.full"  # decompressed frames
AUDIO_CACHE="$CACHE_DIR/roll.s16"       # raw 8kHz signed 16-bit PCM

running=1
audpid=0
cleaned=0

restore_tty() {
  # Restore terminal regardless of state
  echo -e "\x1b[2J \x1b[0H ${purp}<3 \x1b[?25h \x1b[u \x1b[m"
}

# Stop loop first; don't delete cache yet.
request_stop() {
  running=0
}

# Final cleanup after everything is stopped
cleanup() {
  (( cleaned == 1 )) && return
  cleaned=1
  # Kill all children in our process group (video/audio/sox/etc.)
  # Ignore errors in case they're already gone.
  kill -- -$$ 2>/dev/null || true
  # Small grace period to let children exit
  sleep 0.05
  rm -rf "$CACHE_DIR" 2>/dev/null || true
  restore_tty
}

# Handle Ctrl-C, timeout TERM, and HUP
trap 'request_stop' INT TERM HUP
trap 'cleanup' EXIT

# ---------- Net fetch helper ----------
obtainium() {
  if has? curl; then curl -s -L "$1"
  elif has? wget; then wget -q -O - "$1"
  else echo "Cannot has internets. :(" >&2; exit 1
  fi
}

echo -en "\x1b[?25l \x1b[2J \x1b[H"  # Hide cursor, clear screen.

# ---------- Prefetch (once per run) ----------
if [ ! -s "$VIDEO_CACHE" ]; then
  echo -e "${yell}Caching video..."
  # If bunzip2 fails, don't create a zero-length file.
  tmpfile="$VIDEO_CACHE.tmp"
  if obtainium "$video" | bunzip2 -q >"$tmpfile" 2>/dev/null; then
    mv -f "$tmpfile" "$VIDEO_CACHE"
  else
    rm -f "$tmpfile"
    echo -e "${red}Failed to cache video.${yell} Check network/bunzip2." >&2
    exit 1
  fi
fi

if [ ! -s "$AUDIO_CACHE" ]; then
  echo -e "${yell}Caching audio..."
  tmpfile="$AUDIO_CACHE.tmp"
  if obtainium "$audio_raw" >"$tmpfile" 2>/dev/null; then
    mv -f "$tmpfile" "$AUDIO_CACHE"
  else
    rm -f "$tmpfile"
    echo -e "${red}Failed to cache audio.${yell} Check network." >&2
    exit 1
  fi
fi

# ---------- Audio per loop ----------
start_audio() {
  if has? afplay; then
    afplay "$AUDIO_CACHE" &
  elif has? aplay; then
    aplay -Dplug:default -q -f S16_LE -r 8000 "$AUDIO_CACHE" &
  elif has? play; then
    # sox can read raw S16 directly
    play -q -t s16 -r 8000 -c 1 "$AUDIO_CACHE" &
  else
    return 0
  fi
  audpid=$!
}

# ---------- One pass of video with timing ----------
play_video_once() {
python3 <(cat <<'EOF'
import sys, time, signal, os
fps = 25
tpf = 1.0 / fps
buf = ''
frame = 0
next_frame = 0
begin = time.time()

# Exit fast on SIGINT/SIGTERM (from parent)
def _exit(*_):
    # Flush whatever is buffered, then quit
    try:
        if buf:
            sys.stdout.write(buf)
    except Exception:
        pass
    sys.exit(0)

signal.signal(signal.SIGINT, _exit)
signal.signal(signal.SIGTERM, _exit)
signal.signal(signal.SIGHUP, _exit)

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for i, line in enumerate(f):
            if i % 32 == 0:
                frame += 1
                if buf:
                    sys.stdout.write(buf); buf = ''
                elapsed = time.time() - begin
                repose = (frame * tpf) - elapsed
                if repose > 0.0:
                    time.sleep(repose)
                next_frame = elapsed / tpf
            if frame >= next_frame:
                buf += line
        if buf:
            sys.stdout.write(buf)
except FileNotFoundError:
    # Parent might be shutting down; just exit quietly
    pass
except KeyboardInterrupt:
    pass
EOF
) "$VIDEO_CACHE"
}

# ---------- Main loop ----------
while (( running )); do
  start_audio
  play_video_once
  # Sync: if audio still going, wait until it finishes unless we're stopping
  if (( audpid > 1 )); then
    wait "$audpid" 2>/dev/null || true
  fi
done

# When loop exits due to signal/timeout, cleanup trap will run and remove cache.
exit 0
