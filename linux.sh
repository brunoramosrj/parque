#!/bin/bash

# =========================================================================
#
#          SCRIPT DE INVENTÁRIO PARA SISTEMAS LINUX (BASH) - v6 (Final Corrigido)
#
# =========================================================================

# --- CONFIGURAÇÃO ---
PROJECT_DIR="/mnt/parque3.0"

# --- Verificação de Root e Dependências ---
if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Este script precisa ser executado como root (sudo ./linux.sh)"
  exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERRO: O comando 'jq' não foi encontrado. Por favor, instale-o (ex: sudo apt install jq)."
    exit 1
fi

# --- Caminhos e Variáveis Globais ---
HTML_FILE="$PROJECT_DIR/inventario_web.html"
INVENTORY_DIR="$PROJECT_DIR/inventario"
AGGREGATED_JSON_PATH="$INVENTORY_DIR/inventario_web.json"
HOSTNAME=$(hostname)
DATA_HORA=$(date +"%Y-%m-%d %H:%M:%S")
STOPWATCH_START=$(date +%s.%N)

echo "Iniciando coleta de dados para $HOSTNAME..."
mkdir -p "$INVENTORY_DIR"

# --- FUNÇÕES DE COLETA AUXILIARES ---
get_data() {
    local result
    result=$(LC_ALL=C eval "$1" 2>/dev/null)
    if [ -z "$result" ]; then
        echo "$2"
    else
        echo "$result"
    fi
}

remove_accents() {
    echo "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT
}

# --- COLETA DE DADOS ---
echo "Coletando informações..."

declare -A data
data["Computador"]="$HOSTNAME"
data["Usuario"]=$(get_data "logname" "$USER")
data["IP"]=$(get_data "hostname -I | awk '{print \$1}'" "Nao encontrado")
DEFAULT_IFACE=$(get_data "ip route | grep default | awk '{print \$5}'" "")
data["MAC"]=$(get_data "ip link show $DEFAULT_IFACE | grep 'link/ether' | awk '{print \$2}' | tr '[:lower:]' '[:upper:]' | sed 's/:/-/g'" "Nao encontrado")
data["Computador_Fabricante"]=$(get_data "dmidecode -s system-manufacturer" "Indisponivel")
data["Computador_Modelo"]=$(get_data "dmidecode -s system-product-name" "Indisponivel")
data["Computador_Serial"]=$(get_data "dmidecode -s system-serial-number" "Indisponivel")
data["Chassis_Tipo"]=$(get_data "dmidecode -s chassis-type | sed 's/.*/\u&/'" "Indisponivel")
data["SO"]=$(get_data "grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"'" "Indisponivel")
data["Build"]=$(get_data "uname -r" "")
ROOT_DEV=$(get_data "df / | awk 'NR==2 {print \$1}'")
INSTALL_DATE_RAW=$(get_data "tune2fs -l $ROOT_DEV 2>/dev/null | grep 'Filesystem created:'")
if [ -n "$INSTALL_DATE_RAW" ]; then
    INSTALL_DATE=$(date -d "$(echo $INSTALL_DATE_RAW | cut -d':' -f2- | xargs)" +"%Y-%m-%d" 2>/dev/null)
else
    INSTALL_DATE=$(get_data "stat -c %y /etc/fstab | awk '{print \$1}'" "Nao Coletado")
fi
data["Data_Instalacao"]="$INSTALL_DATE"
UPTIME_SECONDS=$(get_data "cat /proc/uptime | awk '{print \$1}'" "0")
data["Uptime_Horas"]=$(awk -v sec="$UPTIME_SECONDS" 'BEGIN { printf "%.1f", sec/3600 }')
data["Uptime_Formatado"]=$(get_data "uptime -p" "Indisponivel")
data["Dominio_ou_Grupo"]=$(get_data "dnsdomainname" "$(hostname -d)")
data["Status_Ativacao"]="N/A"; data["Canal_Licenca"]="N/A"; data["Chave_Parcial"]="N/A"; data["Chave_OEM_BIOS"]="N/A"
CPU_NAME=$(get_data "lscpu | grep 'Model name:' | sed 's/.*:[[:space:]]*//' | sed 's/ Six-Core Processor//'")
CPU_SPEED_MHZ=$(get_data "lscpu | grep 'CPU max MHz:' | sed 's/.*:[[:space:]]*//' | cut -d'.' -f1")
CPU_SPEED_GHZ=$(awk -v mhz="$CPU_SPEED_MHZ" 'BEGIN {printf "%.1f", mhz/1000}')
data["CPU"]="$CPU_NAME @ ${CPU_SPEED_GHZ}GHz"
data["Arquitetura"]=$(get_data "uname -m" "")
data["CPU_Cores"]=$(get_data "lscpu | grep '^Core(s) per socket:' | sed 's/.*:[[:space:]]*//'" "0")
data["CPU_Threads"]=$(get_data "lscpu | grep '^CPU(s):' | sed 's/.*:[[:space:]]*//'" "0")
data["CPU_Clock_MHz"]="$CPU_SPEED_MHZ"
data["PlacaMae_Fabricante"]=$(get_data "dmidecode -s baseboard-manufacturer" "Indisponivel")
data["PlacaMae_Modelo"]=$(get_data "dmidecode -s baseboard-product-name" "Indisponivel")
data["PlacaMae_Serial"]=$(get_data "dmidecode -s baseboard-serial-number" "Indisponivel")
data["BIOS_Versao"]=$(get_data "dmidecode -s bios-version" "Indisponivel")
BIOS_DATE_RAW=$(get_data "dmidecode -s bios-release-date" "")
if [[ "$BIOS_DATE_RAW" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{4})$ ]]; then
    data["BIOS_Data"]="${BASH_REMATCH[3]}-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
else
    data["BIOS_Data"]="$BIOS_DATE_RAW"
fi
data["RAM_GB_Total"]=$(get_data "awk '/MemTotal/ {printf \"%d\", \$2/1024/1024 + 0.5}' /proc/meminfo" "0")
data["Qtd_Pentes"]=$(get_data "dmidecode -t memory | grep -c 'Size: .*[GM]B'" "0")

# CORREÇÃO: RAM_Detalhes - Lógica do awk reescrita para ser universalmente compatível.
data["RAM_Detalhes"]=$(get_data "dmidecode -t 17 | awk '
    function print_ram() {
        if (!type) type = \"N/A\";
        if (!speed) speed = \"N/A\";
        if (!mfg) mfg = \"N/A\";
        printf \"[%s/%s/%s/%s]\", size, type, speed, mfg;
    }
    /Memory Device/ {
        if (size && size !~ /No Module/) {
            print_ram();
            printf \"; \";
        }
        size=\"\"; type=\"\"; speed=\"\"; mfg=\"\";
    }
    /Size: .*B/ { size = \$2 \" \" \$3 }
    /Type: / { type = \$2 }
    /Speed: .*MT\\/s|MHz/ { speed = \$2 \" \" \$3 }
    /Manufacturer: / { mfg = \$2 }
    END {
        if (size && size !~ /No Module/) {
            print_ram();
        }
    }' | sed 's/; $//' | tr -d '\n'" "Falha ao ler RAM")


ROOT_PART_INFO=$(df -BG /)
data["Armazenamento_C_GB"]=$(get_data "echo \"$ROOT_PART_INFO\" | awk 'NR==2 {print \$2}' | tr -d 'G'" "0")
data["Espaco_Livre_C_GB"]=$(get_data "echo \"$ROOT_PART_INFO\" | awk 'NR==2 {print \$4}' | tr -d 'G'" "0")
data["Espaco_Livre_C_Perc"]=$(get_data "echo \"$ROOT_PART_INFO\" | awk 'NR==2 {print \$5}' | tr -d '%'" "0")
data["Discos_Fisicos"]=$(get_data "lsblk -dno TYPE,MODEL,SIZE | grep 'disk' | awk '{printf \"%s - %s (%s) | \", \$1, \$2, \$3}' | sed 's/ | \$//'" "Falha ao ler discos")
data["Volumes"]=$(get_data "df -h | grep '^/dev/' | awk '{printf \"[%s: %s livre de %s]; \", \$1, \$4, \$2}' | sed 's/; \$//'" "Falha ao ler volumes")
ROOT_DEV=$(df / | awk 'NR==2 {print $1}')
ROOT_DISK=$(echo $ROOT_DEV | sed 's/[0-9]*$//' | sed 's|/dev/||')
data["Modelo_Disco_Principal"]=$(get_data "lsblk -dno MODEL /dev/$ROOT_DISK | tail -n 1" "Indisponivel")
data["GPU"]=$(get_data "lspci | grep -i 'VGA\\|3D\\|2D' | sed 's/.*: //'" "Indisponivel")
MONITORS_INFO=$(get_data "xrandr --query 2>/dev/null | grep ' connected' | awk '{print \$1 \" (\" \$3 \")\"}' | paste -sd '; '" "")
data["Monitores"]=${MONITORS_INFO:-"Nenhum monitor detectado"}
data["Resolucao_Tela"]=$(get_data "xrandr | grep '*' | awk '{print \$1}' | head -n 1" "Indisponivel")
BATTERY=$(upower -e | grep 'BAT')
data["Bateria"]=$(get_data "upower -i $BATTERY | grep 'percentage:' | awk '{print \$2}'" "Desktop/Sem bateria")
data["Impressoras"]=$(get_data "lpstat -p | awk '{print \$2}' | paste -sd '; '" "Nenhuma impressora instalada")
AV_STATUS="Desconhecido"
if command -v clamscan &> /dev/null; then AV_STATUS="ClamAV"; fi
if systemctl is-active --quiet clamav-daemon; then AV_STATUS_DETAIL="Ativo"; else AV_STATUS_DETAIL="Inativo"; fi
data["Antivirus"]="$AV_STATUS"; data["Antivirus_Status"]="$AV_STATUS_DETAIL"
FW_STATUS="Nao"
if systemctl is-active --quiet ufw || systemctl is-active --quiet firewalld; then FW_STATUS="Sim"; fi
data["Firewall_Ativo"]="$FW_STATUS"
data["Usa_WSUS"]="N/A"; data["Servidor_WSUS"]=""
data["DataHora_Coleta"]="$DATA_HORA"
data["AdminsLocais"]=$(get_data "(getent group sudo || getent group wheel) | cut -d: -f4 | tr ',' ';'" "Nao Coletado")
UPDATES="Nao Coletado"
if command -v apt-get &> /dev/null; then UPDATES=$(get_data "apt-get -s upgrade | grep -c '^Inst'"); fi
if command -v yum &> /dev/null; then UPDATES=$(yum check-update -q | wc -l); fi
data["UpdatesPendentes"]="$UPDATES"
data["UltimaInstalacaoUpdates"]=$(get_data "grep 'upgrade ' /var/log/dpkg.log | tail -1 | awk '{print \$1}'" "Nao Coletado")
data["PortasTCP_Abertas"]=$(get_data "ss -tlpn | grep LISTEN | awk '{print \$4}' | sed 's/.*://' | sort -un | paste -sd ',' -" "Nao Coletado")
data["PortasUDP_Abertas"]=$(get_data "ss -ulpn | awk '{print \$5}' | sed 's/.*://' | sort -un | paste -sd ',' -" "Nao Coletado")
data["SaudeDiscoSMART"]=$(get_data "smartctl -H /dev/$ROOT_DISK | grep 'test result' | awk '{print \$NF}'" "Nao Coletado")
data["NumeroSerieMonitores"]=$(get_data "edid-decode < /sys/class/drm/card*-*/edid 2>/dev/null | grep 'Serial Number' | awk '{print \$3}'" "Nao Coletado")
data["GatewayPadrao"]=$(get_data "ip route | grep default | awk '{print \$3}'" "Nao Coletado")
data["ServidoresDNS"]=$(get_data "grep nameserver /etc/resolv.conf | awk '{print \$2}' | paste -sd ',' -" "Nao Coletado")
data["ServidorDHCP"]=$(get_data "grep 'dhcp-server-identifier' /var/lib/dhcp/dhclient.leases 2>/dev/null | tail -1 | awk '{print \$3}' | tr -d ';'" "Nao Coletado")
data["DHCPAtivado"]=$(get_data "nmcli dev show $DEFAULT_IFACE 2>/dev/null | grep 'IP4.CONFIG' -A 2 | grep 'method' | awk '{print \$2 == \"auto\"}'" "false")
data["ConsumoCPU_Percentual"]=$(get_data "mpstat 1 1 | awk '/Average/ {print 100 - \$NF}'" "0")
data["ConsumoRAM_Percentual"]=$(get_data "free | grep Mem | awk '{printf \"%.2f\", \$3/\$2 * 100.0}'" "0")
data["Top5ProcessosCPU"]=$(get_data "ps -eo comm,pcpu --sort=-pcpu | head -n 6 | tail -n 5 | awk '{printf \"%s (%.1f%%); \", \$1, \$2}' | sed 's/; \$//'" "Nao Coletado")
data["Top5ProcessosRAM"]=$(get_data "ps -eo comm,pmem --sort=-pmem | head -n 6 | tail -n 5 | awk '{printf \"%s (%.1f%%); \", \$1, \$2}' | sed 's/; \$//'" "Nao Coletado")

# --- CONSTRUÇÃO DO JSON FINAL ---
echo "Construindo objeto JSON..."
json_output=$(jq -n '{}')
readarray -t sorted_keys < <(printf '%s\n' "${!data[@]}" | sort)
for key in "${sorted_keys[@]}"; do
    value=$(remove_accents "${data[$key]}")
    if [[ $value =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        json_output=$(echo "$json_output" | jq --arg key "$key" --argjson val "$value" '.[$key] = $val')
    else
        json_output=$(echo "$json_output" | jq --arg key "$key" --arg val "$value" '.[$key] = $val')
    fi
done

# --- GRAVAÇÃO SEGURA NO HTML ---
echo "Tentando gravar de forma segura no arquivo: $HTML_FILE"
LOCK_FILE="/var/lock/inventory_html.lock"; exec 200>"$LOCK_FILE"; flock -x 200
if [ ! -f "$HTML_FILE" ]; then
    echo "ERRO: Arquivo HTML template não encontrado em $HTML_FILE."; flock -u 200; exit 1;
fi
backup_stamp=$(date +%Y%m%d%H%M%S)
backup_file="$INVENTORY_DIR/inventario_web.${backup_stamp}.bak.html"
if cp --preserve=mode,ownership,timestamps "$HTML_FILE" "$backup_file"; then
    echo "Backup do HTML original criado em $backup_file"
else
    flock -u 200
    echo "ERRO: não foi possível criar o backup de $HTML_FILE em $backup_file." >&2
    exit 1
fi
echo "Atualizando bloco JSON no HTML (modo robusto)..."
temp_html=$(mktemp "$(dirname "$HTML_FILE")/inventario_web.html.XXXXXX")
trap 'rm -f "$temp_html"' EXIT
current_content=$(cat "$HTML_FILE")
marker_counts=$(printf '%s\n' "$current_content" | awk '
    {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        if (line == "//<DATA_START>") starts++
        if (line == "//<DATA_END>") ends++
    }
    END { printf "%d %d", starts + 0, ends + 0 }
')
start_count=${marker_counts%% *}
end_count=${marker_counts##* }
if [ "$start_count" -lt 1 ] || [ "$end_count" -lt 1 ]; then
    flock -u 200
    echo "ERRO: HTML invalido: marcadores //<DATA_START>/ //<DATA_END> nao encontrados." >&2
    exit 1
fi
if [ "$start_count" -gt 1 ] || [ "$end_count" -gt 1 ]; then
    echo "AVISO: HTML continha blocos de dados duplicados; a regravacao vai manter apenas o primeiro bloco dentro do script."
fi
before_data=$(printf '%s\n' "$current_content" | awk '
    {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        if (line == "//<DATA_START>") exit
        print
    }
')
json_part=$(printf '%s\n' "$current_content" | awk '
    {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        if (line == "//<DATA_START>" && !captured) { in_block = 1; next }
        if (line == "//<DATA_END>" && in_block) { captured = 1; in_block = 0; exit }
        if (in_block) print
    }
' | sed 's/^[[:space:]]*var inventoryData = //; s/;[[:space:]]*$//')
after_data=$(printf '%s\n' "$current_content" | awk '
    {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        if (!after_first && line == "//<DATA_END>") { after_first = 1; next }
        if (!after_first) next
        if (line == "//<DATA_START>") { skip_extra = 1; next }
        if (skip_extra && line == "//<DATA_END>") { skip_extra = 0; next }
        if (!skip_extra) print
    }
')
if [ -z "$(printf '%s' "$json_part" | tr -d '[:space:]')" ]; then json_part="[]"; fi
updated_json=$(printf '%s\n' "$json_part" | jq --argjson new_entry "$json_output" '[.[] | select(.Computador != $new_entry.Computador)] + [$new_entry]') || {
    echo "ERRO: falha ao processar JSON atual com jq."; flock -u 200; exit 1;
}
printf '%s\n' "$before_data" > "$temp_html"
printf '%s\n' "//<DATA_START>" >> "$temp_html"
printf '    var inventoryData = %s;\n' "$updated_json" >> "$temp_html"
printf '%s\n' "    //<DATA_END>" >> "$temp_html"
printf '%s\n' "$after_data" >> "$temp_html"
finalize_html_update() {
    if ! printf '%s\n' "$updated_json" > "$AGGREGATED_JSON_PATH"; then
        flock -u 200
        echo "ERRO: não foi possível atualizar o JSON agregado em $AGGREGATED_JSON_PATH." >&2
        exit 1
    fi
    flock -u 200
    echo "$1"
}
mv_err_file=$(mktemp)
if mv -f "$temp_html" "$HTML_FILE" 2>"$mv_err_file"; then
    mv_exit=$?
    rm -f "$mv_err_file"
    finalize_html_update "Arquivo HTML atualizado com sucesso."
else
    mv_exit=$?
    mv_err_msg=$(cat "$mv_err_file")
    rm -f "$mv_err_file"
    if printf '%s' "$mv_err_msg" | grep -qiE 'Permission denied|Operation not permitted'; then
        echo "Aviso: mv falhou com código $mv_exit devido a permissão. Tentando fallback..." >&2
        if cat "$temp_html" > "$HTML_FILE"; then
            finalize_html_update "Arquivo HTML atualizado com sucesso via fallback."
        else
            flock -u 200
            echo "ERRO: fallback de escrita falhou para $HTML_FILE." >&2
            exit 1
        fi
    else
        flock -u 200
        printf '%s\n' "$mv_err_msg" >&2
        echo "ERRO: não foi possível atualizar o arquivo HTML em $HTML_FILE (código $mv_exit)." >&2
        exit 1
    fi
fi
trap - EXIT

# --- SALVAR ARQUIVOS INDIVIDUAIS E CORRIGIR PERMISSÕES ---
JSON_DESTINO="$INVENTORY_DIR/$HOSTNAME.json"
echo "$json_output" > "$JSON_DESTINO"
echo "Inventário individual salvo em $JSON_DESTINO"
HTML_DESTINO="$INVENTORY_DIR/$HOSTNAME.html"
echo "Gerando relatório HTML individual..."
html_rows=""
for key in "${sorted_keys[@]}"; do
    value=${data[$key]:-"Indisponivel"}
    html_rows+="<tr><td><b>$key</b></td><td>$value</td></tr>"
done
cat > "$HTML_DESTINO" <<EOF
<!DOCTYPE html><html lang='pt-BR'><head><meta charset='UTF-8'><title>Inventario - $HOSTNAME</title><style>body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; margin: 0; background-color: #f4f7f9; color: #333; } .container { max-width: 1000px; margin: 40px auto; padding: 20px; background-color: #fff; box-shadow: 0 4px 8px rgba(0,0,0,0.1); border-radius: 8px; } h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; } p.subtitle { font-style: italic; color: #7f8c8d; margin-top: -10px; margin-bottom: 30px; } table { width: 100%; border-collapse: collapse; margin-top: 10px; } td { padding: 10px 12px; border: 1px solid #e0e0e0; vertical-align: top; word-break: break-all; } tr:nth-child(even) { background-color: #f8f9fa; } td:first-child { width: 25%; background-color: #ecf0f1; font-weight: bold; color: #34495e; }</style></head><body><div class='container'><h1>Inventario - $HOSTNAME</h1><p class='subtitle'><i>Gerado em $DATA_HORA</i></p><h2>Detalhes da Coleta</h2><table>$html_rows</table></div></body></html>
EOF
echo "Relatório individual salvo em $HTML_DESTINO"

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$HTML_FILE" "$JSON_DESTINO" "$HTML_DESTINO" "$AGGREGATED_JSON_PATH" 2>/dev/null
    echo "Permissões dos arquivos gerados corrigidas para o usuário '$SUDO_USER'."
fi

STOPWATCH_END=$(date +%s.%N)
RUNTIME=$(echo "$STOPWATCH_END - $STOPWATCH_START" | bc)
# CORREÇÃO: Adicionado LC_ALL=C para o printf final, evitando o erro de "número inválido".
LC_ALL=C printf "\nTempo total de execucao: %.2f segundos\n" $RUNTIME
