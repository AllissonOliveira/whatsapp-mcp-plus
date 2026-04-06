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
    go build -o whatsapp-bridge main.go
    ok "Bridge compilado"
    cd "$SCRIPT_DIR"
}

# ---------- Registrar no claude.json ----------
register_mcp() {
    echo ""
    echo -e "  ${BOLD}Registrando MCP no Claude Code...${RESET}"

    # Cria claude.json se nao existe
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

# ---------- Iniciar bridge e abrir QR ----------
start_and_pair() {
    echo ""
    echo -e "  ${BOLD}Iniciando bridge e gerando QR code...${RESET}"
    echo -e "  ${YELLOW}Quando a imagem do QR abrir, escaneie com o WhatsApp.${RESET}"
    echo -e "  ${YELLOW}(WhatsApp > Configuracoes > Aparelhos conectados > Conectar)${RESET}"
    echo ""

    chmod +x "$SCRIPT_DIR/start-bridge.sh"
    "$SCRIPT_DIR/start-bridge.sh" &
    BRIDGE_PID=$!

    # Espera ate 3 minutos pela autenticacao
    TIMEOUT=180
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if grep -q "Successfully authenticated" /tmp/whatsapp-bridge.log 2>/dev/null; then
            echo ""
            ok "WhatsApp conectado com sucesso!"
            return 0
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    aviso "Timeout esperando autenticacao. Voce pode tentar depois com: $SCRIPT_DIR/start-bridge.sh"
    return 0
}

# ============================================================================
# Main
# ============================================================================

check_go
check_uv
check_qrcode
build_bridge
register_mcp

echo ""
echo -e "  ${BOLD}Quer conectar ao WhatsApp agora?${RESET}"
echo -e "  ${BOLD}1${RESET} - Sim, conectar agora"
echo -e "  ${BOLD}2${RESET} - Nao, conecto depois"
echo ""
read -p "  Escolha: " choice

if [ "$choice" = "1" ]; then
    start_and_pair
else
    echo ""
    ok "Para conectar depois, execute: $SCRIPT_DIR/start-bridge.sh"
fi

echo ""
echo -e "${GREEN}${BOLD}  WhatsApp MCP instalado com sucesso!${RESET}"
echo ""
