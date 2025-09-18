#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG =====
# If rickroll.sh sits next to this installer, it will be used.
# Otherwise run: RICK_URL="https://example.com/path/to/rickroll.sh" ./install.sh
RICK_URL="https://raw.githubusercontent.com/onlyHydra/rickroll/refs/heads/main/rickroll.sh"

# ===== Paths =====
INSTALL_DIR="$HOME/.rickroll"
PLAYER="$INSTALL_DIR/rickroll.sh"
RUNNER="$INSTALL_DIR/run.sh"

echo "[*] Creating hidden folder: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# ----- Step 2: Download (or copy) rickroll.sh -----
if [[ -f "./rickroll.sh" ]]; then
  echo "[*] Using local ./rickroll.sh"
  cp "./rickroll.sh" "$PLAYER"
elif [[ -n "$RICK_URL" ]]; then
  echo "[*] Downloading rickroll.sh from \$RICK_URL"
  curl -fsSL "$RICK_URL" -o "$PLAYER"
else
  echo "[-] No ./rickroll.sh found and RICK_URL not set."
  echo "    Put rickroll.sh next to install.sh OR run with:"
  echo "    RICK_URL='https://…/rickroll.sh' ./install.sh"
  exit 1
fi
chmod +x "$PLAYER"

# ----- Step 4 & 5: Wrapper that unmutes -> sets 50% -> runs FOREGROUND (ASCII visible), 45m cap -----
cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

unmute_and_set_50() {
  # -------- PipeWire (wpctl) --------
  if command -v wpctl >/dev/null 2>&1; then
    # Default sink numeric ID (line starting with '*')
    get_wp_default_sink() {
      wpctl status 2>/dev/null | awk '
        /Sinks:/ { inside=1; next }
        /Sources:/ { inside=0 }
        inside && $1=="*" { if (match($0,/([0-9]+)\./,m)) { print m[1]; exit } }'
    }
    # All sink numeric IDs
    list_wp_sinks() {
      wpctl status 2>/dev/null | awk '
        /Sinks:/ { inside=1; next }
        /Sources:/ { inside=0 }
        inside && match($0,/([0-9]+)\./,m) { print m[1] }'
    }
    # Active stream IDs (Sink Inputs)
    list_wp_sink_inputs() {
      wpctl status 2>/dev/null | awk '
        /Sink inputs:/ { inside=1; next }
        /Source outputs:/ { inside=0 }
        inside && match($0,/([0-9]+)\./,m) { print m[1] }'
    }

    def="$(get_wp_default_sink || true)"
    if [[ -n "${def:-}" ]]; then
      wpctl set-mute   "$def" 0 2>/dev/null || true
      wpctl set-volume "$def" 0.50 2>/dev/null || true
    fi
    # Unmute/set all sinks
    while IFS= read -r sid; do
      [[ -n "$sid" ]] || continue
      wpctl set-mute   "$sid" 0 2>/dev/null || true
      wpctl set-volume "$sid" 0.50 2>/dev/null || true
    done < <(list_wp_sinks)
    # Unmute active streams feeding the sink (important!)
    while IFS= read -r iid; do
      [[ -n "$iid" ]] || continue
      wpctl set-mute   "$iid" 0 2>/dev/null || true
      wpctl set-volume "$iid" 0.80 2>/dev/null || true
    done < <(list_wp_sink_inputs)
    return
  fi

  # -------- PulseAudio (pactl) --------
  if command -v pactl >/dev/null 2>&1; then
    # Default sink (name), if supported
    if pactl --help 2>&1 | grep -q 'get-default-sink'; then
      dflt="$(pactl get-default-sink 2>/dev/null || true)"
      if [[ -n "${dflt:-}" ]]; then
        pactl set-sink-mute   "$dflt" 0    2>/dev/null || true
        pactl set-sink-volume "$dflt" 50%  2>/dev/null || true
      fi
    else
      pactl set-sink-mute   @DEFAULT_SINK@ 0   2>/dev/null || true
      pactl set-sink-volume @DEFAULT_SINK@ 50% 2>/dev/null || true
    fi
    # Unmute/set all sinks
    while IFS= read -r sid; do
      pactl set-sink-mute   "$sid" 0    2>/dev/null || true
      pactl set-sink-volume "$sid" 50%  2>/dev/null || true
    done < <(pactl list short sinks 2>/dev/null | awk '{print $1}')
    # Unmute/set all active sink-inputs (app streams)
    while IFS= read -r iid; do
      pactl set-sink-input-mute   "$iid" 0    2>/dev/null || true
      pactl set-sink-input-volume "$iid" 50%  2>/dev/null || true
    done < <(pactl list short sink-inputs 2>/dev/null | awk '{print $1}')
    return
  fi

  # -------- ALSA (amixer) --------
  if command -v amixer >/dev/null 2>&1; then
    # Try pulse device first
    for ctl in Master Speaker Headphone PCM Front 'Line Out'; do
      amixer -D pulse sset "$ctl" 50% unmute >/dev/null 2>&1 || true
    done
    # Fall back to card 0
    for ctl in Master Speaker Headphone PCM Front 'Line Out'; do
      amixer -c 0 sset "$ctl" 50% unmute >/dev/null 2>&1 || true
    done
  fi
}

# Unmute + set volume first
unmute_and_set_50

# Foreground playback with a 45-minute cap:
# - ASCII shows in THIS terminal
# - Ctrl-C stops immediately
# - Closing the terminal stops it (no nohup/disown)
exec timeout 45m "$HOME/.rickroll/rickroll.sh"
EOF
chmod +x "$RUNNER"

# ----- Step 3: Permanent alias for the wrapper (works in new terminals) -----
add_alias() {
  local rc="$1"
  local line="alias rickroll='$RUNNER'"
  [[ -f "$rc" ]] || return 0
  grep -qxF "$line" "$rc" 2>/dev/null || echo "$line" >> "$rc"
}
add_alias "$HOME/.bashrc"
add_alias "$HOME/.zshrc"

echo
echo "[✓] Install complete."
echo "    Folder : $INSTALL_DIR"
echo "    Player : $PLAYER"
echo "    Runner : $RUNNER"
echo
echo "Open a NEW terminal (so the alias loads), then run:"
echo "    rickroll"
echo
echo "Notes:"
echo "  • ASCII plays in your terminal (foreground)."
echo "  • Ctrl-C stops immediately, closing the terminal stops it too."
echo "  • It auto-stops after 45 minutes."
