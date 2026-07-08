#!/bin/bash

# Este script instala as dependências necessárias para o script de inventário (linux.sh)
# em sistemas baseados em Ubuntu/Debian.
#
# Uso:
#   1. Dê permissão de execução: chmod +x install_deps_ubuntu.sh
#   2. Execute com privilégios de root: sudo ./install_deps_ubuntu.sh

# --- Verificação de Root ---
if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Por favor, execute como root (sudo ./install_deps_ubuntu.sh)"
  exit 1
fi

echo ">>> Atualizando a lista de pacotes (apt update)..."
apt-get update

echo ""
echo ">>> Instalando as dependências necessárias..."

apt-get install -y \
    jq \
    dmidecode \
    smartmontools \
    read-edid \
    upower \
    x11-xserver-utils \
    net-tools \
    pciutils \
    sysstat \
    bc \
    iconv

echo ""
echo ">>> Instalação de dependências concluída com sucesso!"
