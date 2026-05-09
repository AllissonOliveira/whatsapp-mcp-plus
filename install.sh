#!/bin/bash
set -e

# ============================================================================
# WhatsApp MCP Plus — Instalador Automatico
# ============================================================================

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BOLD='\033[1m'
RESET='\033[0m'

ok()    { echo -e "  ${GREEN}[OK]${RESET} $1"; }
aviso() { echo -e "  ${YELLOW}[!]${RESET} $1"; }
erro()  { echo -e "  ${RED}[X]${RESET} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/whatsapp-bridge"
MCP_SERVER_DIR="$SCRIPT_DIR/whatsapp-mcp-server"
CLAUDE_JSON="$HOME/.claude.json"
PLIST_PATH="$HOME/Library/LaunchAgents/com.whatsapp-mcp.bridge.plist"

echo ""
echo -e "${BOLD}  WhatsApp MCP Plus — Instalacao${RESET}"
echo ""

# ---------- Go ----------
check_go() {
    if command -v go &>/dev/null; then
        GO_VER=$(go version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        ok "Go $GO_VER encontrado"
        return 0
    fi

    aviso "Go nao encontrado. Instalando..."
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            brew install go
        else
            erro "Instale o Go manualmente: https://go.dev/dl/"
            return 1
        fi
    else
        sudo apt-get update && sudo apt-get install -y golang
    fi

    if command -v go &>/dev/null; then
        ok "Go instalado"
    else
        erro "Falha ao instalar Go. Instale manualmente: https://go.dev/dl/"
        return 1
    fi
}

# ---------- uv ----------
check_uv() {
    if command -v uv &>/dev/null; then
        ok "uv encontrado"
        return 0
    fi

    aviso "uv nao encontrado. Instalando..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"

    if command -v uv &>/dev/null; then
        ok "uv instalado"
    else
        erro "Falha ao instalar uv"
        return 1
    fi
}

# ---------- qrcode Python lib ----------
check_qrcode() {
    if python3 -c "import qrcode" 2>/dev/null; then
        ok "qrcode (Python) encontrado"
        return 0
    fi

    aviso "Instalando qrcode..."
    pip3 install "qrcode[pil]" -q 2>/dev/null || pip install "qrcode[pil]" -q 2>/dev/null
    ok "qrcode instalado"
}

# ---------- Compilar bridge ----------
build_bridge() {
    echo ""
    echo -e "  ${BOLD}Compilando bridge Go...${RESET}"
    cd "$BRIDGE_DIR"
    CGO_ENABLED=1 go build -o whatsapp-bridge main.go
    ok "Bridge compilado"
    cd "$SCRIPT_DIR"
}

# ---------- Registrar no claude.json ----------
register_mcp() {
    echo ""
    echo -e "  ${BOLD}Registrando MCP no Claude Code...${RESET}"

    if [ ! -f "$CLAUDE_JSON" ]; then
        echo '{}' > "$CLAUDE_JSON"
    fi

    python3 -c "
import json, os

path = os.path.expanduser('~/.claude.json')
with open(path) as f:
    data = json.load(f)

data.setdefault('mcpServers', {})
data['mcpServers']['whatsapp'] = {
    'command': 'uv',
    'args': ['--directory', '$MCP_SERVER_DIR', 'run', 'main.py']
}

with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
    ok "WhatsApp MCP registrado em ~/.claude.json"
}

# ---------- Registrar bridge como daemon do sistema (macOS) ----------
register_launchd() {
    if [[ "$(uname)" != "Darwin" ]]; then
        aviso "Launchd nao disponivel neste sistema. Inicie o bridge manualmente com: $SCRIPT_DIR/start-bridge.sh"
        return 0
    fi

    echo ""
    echo -e "  ${BOLD}Registrando bridge como daemon do sistema...${RESET}"

    chmod +x "$SCRIPT_DIR/start-bridge.sh"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.whatsapp-mcp.bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/start-bridge.sh</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/whatsapp-bridge-launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/whatsapp-bridge-launchd.log</string>
</dict>
</plist>
PLIST_EOF

    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"
    ok "Bridge registrado como daemon — inicia automaticamente no login e reinicia se craschar"
}

# ============================================================================
# Main
# ============================================================================

check_go
check_uv
check_qrcode
build_bridge
register_mcp
register_launchd

echo ""
echo -e "${GREEN}${BOLD}  WhatsApp MCP instalado com sucesso!${RESET}"
echo ""
echo -e "  ${YELLOW}Proximos passos:${RESET}"
echo -e "  1. Abra o Claude Code"
echo -e "  2. Chame a ferramenta ${BOLD}setup_whatsapp${RESET}"
echo -e "  3. Escaneie o QR code com o WhatsApp"
echo -e "  4. Reinicie o Claude Code"
echo ""
