#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$SCRIPT_DIR/whatsapp-bridge/whatsapp-bridge"
LOG="/tmp/whatsapp-bridge.log"
QR_DATA="/tmp/wa_qr_data.txt"
QR_PNG="/tmp/wa_qrcode.png"
LOCK="/tmp/whatsapp-bridge.lock"

# Single-instance guard
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
    echo "Bridge já está rodando (PID $(cat "$LOCK"))"
    exit 0
fi

# Kill stale processes and free port 8080
pkill -f "whatsapp-bridge" 2>/dev/null
lsof -ti :8080 | xargs kill -9 2>/dev/null
sleep 1

# Clean old QR artifacts
rm -f "$QR_DATA" "$QR_PNG"

# Start bridge in background
"$BRIDGE" > "$LOG" 2>&1 &
BRIDGE_PID=$!
echo "$BRIDGE_PID" > "$LOCK"
trap "rm -f '$LOCK'" EXIT

# Monitor log — only open QR PNG when SESSION is new (QR_NEEDED signal)
QR_OPENED=0
while kill -0 "$BRIDGE_PID" 2>/dev/null; do
    if [ "$QR_OPENED" -eq 0 ] && grep -q "QR_NEEDED" "$LOG" 2>/dev/null; then
        QR_OPENED=1
        sleep 0.5
        python3 -c "
import qrcode
try:
    data = open('$QR_DATA').read().strip()
    img = qrcode.make(data)
    img.save('$QR_PNG')
except: pass
" 2>/dev/null
        if [ -f "$QR_PNG" ]; then
            osascript -e 'tell application "Preview" to close (every window whose name contains "wa_qrcode")' 2>/dev/null
            open "$QR_PNG" 2>/dev/null || xdg-open "$QR_PNG" 2>/dev/null
        fi
    fi
    sleep 1
done

wait "$BRIDGE_PID"
