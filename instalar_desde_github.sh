#!/bin/bash
set -e

# Reemplaza esta URL por tu repositorio real.
INSTALLER_URL="https://raw.githubusercontent.com/TU_USUARIO/TU_REPO/main/instalar.sh"

echo "========================================"
echo " SVRCODE - INSTALACIÓN DESDE GITHUB"
echo "========================================"

cd /root
apt update
apt install -y wget curl unzip git

rm -f instalar.sh
wget -O instalar.sh "$INSTALLER_URL"
chmod +x instalar.sh
bash instalar.sh
