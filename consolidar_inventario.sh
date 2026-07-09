#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
HTML_FILE="inventario_web.html"
HTML_TEMPLATE_FILE="inventario_web.template.html"
INVENTORY_DIR="inventario"
MARCADOR_DADOS_INI="//<DATA_START>"
MARCADOR_DADOS_FIM="//<DATA_END>"
CONFIG_FILE="$SCRIPT_DIR/parque.conf"

if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) continue ;;
        esac
        case "$line" in
            *=*)
                key="${line%%=*}"
                val="${line#*=}"
                key="$(echo "$key" | xargs)"
                val="${val%${val##*[![:space:]]}}"
                val="${val#"${val%%[![:space:]]*}"}"
                case "$key" in
                    PROJECT_DIR)        [ -n "$val" ] && PROJECT_DIR="$val" ;;
                    HTML_FILE)          [ -n "$val" ] && HTML_FILE="$val" ;;
                    HTML_TEMPLATE_FILE) [ -n "$val" ] && HTML_TEMPLATE_FILE="$val" ;;
                    INVENTORY_DIR)      [ -n "$val" ] && INVENTORY_DIR="$val" ;;
                    MARCADOR_DADOS_INI) [ -n "$val" ] && MARCADOR_DADOS_INI="$val" ;;
                    MARCADOR_DADOS_FIM) [ -n "$val" ] && MARCADOR_DADOS_FIM="$val" ;;
                esac
                ;;
        esac
    done < "$CONFIG_FILE"
fi

resolve_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        '') printf '%s\n' "$PROJECT_DIR/$2" ;;
        *)  printf '%s\n' "$PROJECT_DIR/$1" ;;
    esac
}

HTML_FILE="$(resolve_path "$HTML_FILE" "inventario_web.html")"
HTML_TEMPLATE_FILE="$(resolve_path "$HTML_TEMPLATE_FILE" "inventario_web.template.html")"
INVENTORY_DIR="$(resolve_path "$INVENTORY_DIR" "inventario")"
AGGREGATED_JSON_FILE="$INVENTORY_DIR/inventario_web.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "ERRO: jq nao encontrado. Instale com: sudo apt install jq" >&2
    exit 1
fi

if [ ! -d "$INVENTORY_DIR" ]; then
    echo "ERRO: Pasta de inventario nao encontrada: $INVENTORY_DIR" >&2
    exit 1
fi

if [ ! -f "$HTML_FILE" ]; then
    if [ -f "$HTML_TEMPLATE_FILE" ]; then
        cp "$HTML_TEMPLATE_FILE" "$HTML_FILE"
        echo "HTML operacional criado a partir do template: $HTML_FILE"
    else
        echo "ERRO: HTML nao encontrado em $HTML_FILE e template nao encontrado em $HTML_TEMPLATE_FILE" >&2
        exit 1
    fi
fi

tmp_json="$(mktemp)"
tmp_items="$(mktemp)"
printf '%s\n' '[]' > "$tmp_items"

while IFS= read -r -d '' json_file; do
    if ! item="$(jq -c 'select(type == "object" and (.Computador // "") != "")' "$json_file" 2>/dev/null)"; then
        echo "AVISO: ignorando JSON invalido: $json_file" >&2
        continue
    fi
    if [ -z "$item" ]; then
        echo "AVISO: ignorando JSON sem campo Computador: $json_file" >&2
        continue
    fi
    updated_items="$(mktemp)"
    jq --argjson item "$item" '. + [$item]' "$tmp_items" > "$updated_items"
    mv "$updated_items" "$tmp_items"
done < <(find "$INVENTORY_DIR" -maxdepth 1 -type f -name '*.json' ! -name 'inventario_web.json' -print0)

jq 'unique_by(.Computador) | sort_by(.Computador)' "$tmp_items" > "$tmp_json"

if [ ! -s "$tmp_json" ]; then
    printf '[]\n' > "$tmp_json"
fi

cp "$tmp_json" "$AGGREGATED_JSON_FILE"

lock_file="$HTML_FILE.lock"
exec 200>"$lock_file"
flock -x 200

backup_file="$HTML_FILE.$(date +%Y%m%d%H%M%S).bak.html"
cp "$HTML_FILE" "$backup_file"

tmp_html="$(mktemp)"
awk -v start="$MARCADOR_DADOS_INI" -v end="$MARCADOR_DADOS_FIM" -v json_file="$tmp_json" '
    BEGIN {
        while ((getline line < json_file) > 0) {
            json = json line "\n"
        }
        close(json_file)
    }
    {
        trimmed = $0
        sub(/^[[:space:]]*/, "", trimmed)
        sub(/[[:space:]]*$/, "", trimmed)
        if (trimmed == start) {
            print $0
            printf "    var inventoryData = %s;\n", json
            in_block = 1
            next
        }
        if (trimmed == end && in_block) {
            print $0
            in_block = 0
            next
        }
        if (!in_block) print $0
    }
' "$HTML_FILE" > "$tmp_html"

if ! grep -Fq "$MARCADOR_DADOS_INI" "$tmp_html" || ! grep -Fq "$MARCADOR_DADOS_FIM" "$tmp_html"; then
    echo "ERRO: marcadores nao encontrados no HTML." >&2
    rm -f "$tmp_json" "$tmp_items" "$tmp_html"
    exit 1
fi

mv "$tmp_html" "$HTML_FILE"
rm -f "$tmp_json" "$tmp_items"
flock -u 200

count="$(jq 'length' "$AGGREGATED_JSON_FILE")"
echo "Inventario consolidado com $count registros."
echo "JSON agregado: $AGGREGATED_JSON_FILE"
echo "HTML atualizado: $HTML_FILE"
