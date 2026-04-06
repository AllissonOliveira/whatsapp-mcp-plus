#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$SCRIPT_DIR/whatsapp-bridge/whatsapp-bridge"
LOG="/tmp/whatsapp-bridge.log"
QR_DATA="/tmp/wa_qr_data.txt"
QR_PNG="/tmp/wa_qrcode.png"

# Kill any existing bridge instances
pkill -f "whatsapp-bridge" 2>/dev/null
sleep 2

# Free port 8080 if still in use
lsof -ti :8080 | xargs kill -9 2>/dev/null
sleep 1

# Start bridge and monitor output
"$BRIDGE" 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$LOG"

    # Save QR data when detected
    if echo "$line" | grep -q "Scan this QR code"; then
        # Next non-empty line will be QR data - captured by instaloader patch
        :
    fi

    # Auto-generate QR PNG, open it and notify
    if echo "$line" | grep -q "QR data saved"; then
        sleep 0.5
        python3 -c "
import qrcode
try:
    data = open('$QR_DATA').read().strip()
    img = qrcode.make(data)
    img.save('$QR_PNG')
except: pass
" 2>/dev/null
        # Abre o QR automaticamente
        if [ -f "$QR_PNG" ]; then
            open "$QR_PNG" 2>/dev/null || xdg-open "$QR_PNG" 2>/dev/null
        fi
        osascript -e "display notification \"QR code aberto — escaneie com o WhatsApp\" with title \"WhatsApp Bridge\" sound name \"Ping\"" 2>/dev/null
    fi

    # Notify on successful connection
    if echo "$line" | grep -q "Successfully authenticated"; then
        osascript -e "display notification \"WhatsApp Bridge conectado com sucesso\" with title \"WhatsApp Bridge\" sound name \"Glass\"" 2>/dev/null
    fi

    # Notify on logout
    if echo "$line" | grep -q "logged out"; then
        osascript -e "display notification \"Sessão encerrada — reconectando...\" with title \"WhatsApp Bridge\" sound name \"Basso\"" 2>/dev/null
    fi
done
