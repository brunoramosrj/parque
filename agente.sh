#!/bin/bash
#
# Agente Parque 3.3 - Linux
#
# Loop que monitora comandos/<HOSTNAME>.json e executa a acao solicitada.
# Suporta: inventario (roda COLETOR_LINUX). Demais acoes -> logadas como
# nao suportadas no Linux e arquivadas. Gera status em retorno/<HOST>.json.
#
# Uso: rode como root (o coletor exige root para dmidecode etc.):
#   sudo ./agente.sh
# ou como servico (systemd/screen) apontando PROJECT_DIR para o share.

set -u

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")" )" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
COMANDOS_DIR="comandos"
EXECUTADOS_DIR="executados"
RETORNO_DIR="retorno"
COLETOR_LINUX="linux.sh"
INTERVALO_AGENTE_SEG=60
CONFIG_FILE="$SCRIPT_DIR/parque.conf"

if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*) continue ;; esac
        case "$line" in
            *=*)
                key="${line%%=*}"; val="${line#*=}"
                key="$(echo "$key" | xargs)"
                val="${val%${val##*[![:space:]]}}"; val="${val#"${val%%[![:space:]]*}"}"
                case "$key" in
                    PROJECT_DIR)          [ -n "$val" ] && PROJECT_DIR="$val" ;;
                    COMANDOS_DIR)         [ -n "$val" ] && COMANDOS_DIR="$val" ;;
                    EXECUTADOS_DIR)      [ -n "$val" ] && EXECUTADOS_DIR="$val" ;;
                    RETORNO_DIR)          [ -n "$val" ] && RETORNO_DIR="$val" ;;
                    COLETOR_LINUX)        [ -n "$val" ] && COLETOR_LINUX="$val" ;;
                    INTERVALO_AGENTE_SEG) [ -n "$val" ] && INTERVALO_AGENTE_SEG="$val" ;;
                esac
                ;;
        esac
    done < "$CONFIG_FILE"
fi

resolve_path() {
    case "$1" in
        /*) echo "$1" ;;
        '') echo "$2" ;;
        *)  echo "$PROJECT_DIR/$1" ;;
    esac
}
COMANDOS_DIR="$(resolve_path "$COMANDOS_DIR" "$PROJECT_DIR/comandos")"
EXECUTADOS_DIR="$(resolve_path "$EXECUTADOS_DIR" "$PROJECT_DIR/executados")"
RETORNO_DIR="$(resolve_path "$RETORNO_DIR" "$PROJECT_DIR/retorno")"
COLETOR_LINUX="$(resolve_path "$COLETOR_LINUX" "$PROJECT_DIR/linux.sh")"

HOSTNAME_BIN="$(hostname)"
COMANDO_PATH="$COMANDOS_DIR/$HOSTNAME_BIN.json"
RETORNO_LOG="$RETORNO_DIR/$HOSTNAME_BIN.log"
STATUS_JSON="$RETORNO_DIR/$HOSTNAME_BIN.json"

mkdir -p "$EXECUTADOS_DIR" "$RETORNO_DIR"

if ! command -v jq >/dev/null 2>&1; then
    echo "ERRO: jq nao encontrado. Instale com: sudo apt install jq" >&2
    exit 1
fi

# Aviso: coletor exige root; sem root a coleta sai parcial.
if [ "$EUID" -ne 0 ]; then
    echo "AVISO: rode como root (sudo ./agente.sh) para coleta completa via $COLETOR_LINUX." >&2
fi

escreve_status() { # acao sucesso codigo mensagem origem arquivado
    jq -n --arg pc "$HOSTNAME_BIN" --arg acao "$1" \
          --argjson sucesso "$2" --argjson codigo "$3" \
          --arg msg "$4" --arg origem "$5" --arg arq "$6" \
          '{Computador:$pc, Acao:$acao, Inicio:$inicio, Fim:$fim,
            Sucesso:$sucesso, CodigoSaida:$codigo, Mensagem:$msg,
            ComandoOrigem:$origem, ArquivoArquivado:$arq, AgenteVersao:"3.3"}' \
          --arg inicio "$ACAO_INICIO" --arg fim "$(date +"%Y-%m-%d %H:%M:%S")" > "$STATUS_JSON"
}

log() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$RETORNO_LOG"; }

echo "Agente iniciado para $HOSTNAME_BIN. Monitorando $COMANDO_PATH ..."

FALHAS_PARSE=0
MAX_FALHAS_PARSE=3

while true; do
    if [ -f "$COMANDO_PATH" ]; then
        echo "Comando encontrado para $HOSTNAME_BIN."
        ACAO_INICIO="$(date +"%Y-%m-%d %H:%M:%S")"
        ACAO="$(jq -r '.acao // empty' "$COMANDO_PATH" 2>/dev/null)"
        if [ -z "$ACAO" ]; then
            FALHAS_PARSE=$((FALHAS_PARSE + 1))
            if [ "$FALHAS_PARSE" -eq 1 ]; then
                log "Erro de parse em $COMANDO_PATH (jq)."
            fi
            if [ "$FALHAS_PARSE" -ge "$MAX_FALHAS_PARSE" ]; then
                DEST="$EXECUTADOS_DIR/$HOSTNAME_BIN.invalido-$(date +%Y%m%d_%H%M%S).json"
                mv -f "$COMANDO_PATH" "$DEST"
                log "JSON inválido arquivado em $DEST após $FALHAS_PARSE tentativas. Corrija e publique novamente em comandos/."
                escreve_status "(parse)" false null "JSON inválido arquivado." "$COMANDO_PATH" "$DEST"
                FALHAS_PARSE=0
            fi
        else
            FALHAS_PARSE=0
            log ""
            log "Iniciando ação: $ACAO"
            OK=true; CODE=null; MSG="ok"
            case "$ACAO" in
                inventario)
                    log "Executando inventário..."
                    if bash "$COLETOR_LINUX" >>"$RETORNO_LOG" 2>&1; then
                        CODE=0; MSG="Coleta concluída. Rode o consolidador para atualizar o dashboard."
                        log "$MSG"
                    else
                        CODE=$?; OK=false; MSG="Coleta terminou com código de saída: $CODE. Verifique o coletor ($COLETOR_LINUX)."
                        log "$MSG"
                    fi
                    ;;
                instalar|desinstalar|executar|copiar)
                    OK=false; MSG="Ação '$ACAO' não suportada no agente Linux. Use o agente Windows."
                    log "$MSG"
                    ;;
                *)
                    OK=false; MSG="Ação desconhecida: $ACAO"
                    log "$MSG"
                    ;;
            esac
            DEST="$EXECUTADOS_DIR/$HOSTNAME_BIN-$(date +%Y%m%d_%H%M%S).json"
            mv -f "$COMANDO_PATH" "$DEST"
            escreve_status "$ACAO" "$OK" "$CODE" "$MSG" "$COMANDO_PATH" "$DEST"
            log "Ação concluída (sucesso: $OK) e comando arquivado em $DEST."
        fi
    fi
    sleep "$INTERVALO_AGENTE_SEG"
done
