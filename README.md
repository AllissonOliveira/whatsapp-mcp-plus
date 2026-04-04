# WhatsApp MCP Plus

Fork melhorado do [whatsapp-mcp](https://github.com/lharries/whatsapp-mcp) com correcoes criticas e otimizacoes de performance.

## O que ha de diferente?

| Feature | Original | MCP Plus |
|---------|----------|----------|
| Mensagens recentes (LID) | Nao encontra | Resolve automaticamente |
| Performance de queries | Full table scan | Indices SQLite otimizados |
| Context fetch (N+1) | 61 queries por chamada | Reutiliza conexao aberta |
| Conexao | Cai e nao volta | Reconexao automatica com backoff |
| Sync de historico | Manual | Automatico a cada 30 min |
| Login QR code | So terminal | Gera PNG + notificacao macOS |
| MCP SDK | v1.6.0 | v1.10.1 |
| Filtro por midia | Nao existe | Filtrar por image/video/audio/document |
| Health check | Nao existe | GET /api/status |
| Nomes em grupo | 1 query por mensagem | Batch lookup |

## Pre-requisitos

- [Go](https://go.dev/dl/) 1.21+
- [Python](https://www.python.org/downloads/) 3.11+
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (gerenciador Python)
- [FFmpeg](https://ffmpeg.org/) (opcional, para mensagens de audio)

## Instalacao

### 1. Clone o repositorio

```bash
git clone https://github.com/SEU_USUARIO/whatsapp-mcp-plus.git
cd whatsapp-mcp-plus
```

### 2. Compile o bridge

```bash
cd whatsapp-bridge
go build -o whatsapp-bridge main.go
```

### 3. Primeira execucao (autenticacao)

```bash
./whatsapp-bridge
```

Um QR code vai aparecer no terminal. Escaneie com:
**WhatsApp > Configuracoes > Aparelhos conectados > Conectar aparelho**

Apos autenticar, a sessao fica salva. Nas proximas vezes, conecta automaticamente.

### 4. Execucoes seguintes (com script)

```bash
cd ..
chmod +x start-bridge.sh
./start-bridge.sh
```

O script:
- Mata instancias anteriores
- Libera a porta 8080
- Gera QR code como PNG em `/tmp/wa_qrcode.png` (se necessario)
- Envia notificacoes macOS

### 5. Configure seu cliente MCP

Descubra o caminho do `uv`:
```bash
which uv
```

#### Claude Code (CLI)

Adicione em `~/.claude/.mcp.json`:

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "/CAMINHO/PARA/uv",
      "args": [
        "--directory",
        "/CAMINHO/PARA/whatsapp-mcp-plus/whatsapp-mcp-server",
        "run",
        "main.py"
      ]
    }
  }
}
```

#### Claude Desktop

Adicione em `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "/CAMINHO/PARA/uv",
      "args": [
        "--directory",
        "/CAMINHO/PARA/whatsapp-mcp-plus/whatsapp-mcp-server",
        "run",
        "main.py"
      ]
    }
  }
}
```

#### Cursor

Adicione em `~/.cursor/mcp.json` (mesmo formato acima).

### 6. Reinicie o cliente

Reinicie o Claude Desktop, Cursor, ou a sessao do Claude Code.

## Tools disponiveis

| Tool | Descricao |
|------|-----------|
| `search_contacts` | Busca contatos por nome ou numero |
| `list_messages` | Lista mensagens com filtros (data, chat, conteudo, tipo de midia) |
| `list_chats` | Lista conversas com ultima mensagem |
| `get_chat` | Metadados de um chat por JID |
| `get_direct_chat_by_contact` | Encontra chat direto pelo numero |
| `get_contact_chats` | Todos os chats de um contato |
| `get_last_interaction` | Ultima mensagem com um contato |
| `get_message_context` | Contexto ao redor de uma mensagem |
| `send_message` | Envia mensagem de texto |
| `send_file` | Envia arquivo (imagem, video, documento) |
| `send_audio_message` | Envia audio como mensagem de voz |
| `download_media` | Baixa midia de uma mensagem |

## Arquitetura

```
WhatsApp Cloud <-> Go Bridge (whatsmeow) <-> SQLite <-> Python MCP Server <-> Claude
                        |
                   REST API :8080
                  /api/send
                  /api/download
                  /api/status
```

1. O **Go Bridge** conecta ao WhatsApp via whatsmeow e armazena tudo em SQLite
2. O **Python MCP Server** le do SQLite e expoe tools via protocolo MCP
3. Para enviar mensagens, o MCP Server chama a REST API do Bridge

## Troubleshooting

### Mensagens nao aparecem para um contato

O WhatsApp migrou para LIDs (Linked Device IDs). Este fork resolve automaticamente. Busque pelo **nome** do contato, nao pelo numero.

### Bridge desconecta

O MCP Plus tem reconexao automatica com backoff exponencial. Se persistir, delete os arquivos em `whatsapp-bridge/store/` e re-autentique.

### QR code nao aparece no terminal

Use `start-bridge.sh` que gera um PNG em `/tmp/wa_qrcode.png`.

### Erro ao compilar no Windows

O `go-sqlite3` requer CGO habilitado:

```bash
cd whatsapp-bridge
go env -w CGO_ENABLED=1
go build -o whatsapp-bridge.exe main.go
```

Voce precisa de um compilador C instalado (ex: [MSYS2](https://www.msys2.org/)).

### Health check

Verifique se o bridge esta rodando:

```bash
curl http://localhost:8080/api/status
```

Retorna: `{"connected": true, "logged_in": true, "timestamp": "..."}`

## Licenca

MIT License. Veja [LICENSE](LICENSE).
