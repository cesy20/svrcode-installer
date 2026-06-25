#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C0='\033[0m'; C1='\033[1;32m'; C2='\033[1;36m'; C3='\033[1;33m'; C4='\033[1;31m'
msg(){ echo -e "${C1}$*${C0}"; }
info(){ echo -e "${C2}$*${C0}"; }
warn(){ echo -e "${C3}$*${C0}"; }
err(){ echo -e "${C4}$*${C0}"; }

if [ "${EUID:-$(id -u)}" != "0" ]; then
  err "ERROR: ejecuta como root"
  exit 1
fi

clear || true
msg "============================================================"
msg " NETVPN INSTALADOR LIMPIO - BASE PROTOCOLOS + MANAGER V7E"
msg "============================================================"
info "Incluye solo: protocolos base + AUTH/API/manager token."
info "No incluye APP. No incluye GEN. No toca APK."
echo

chmod +x \
  "$BASE_DIR/instalar_base.sh" \
  "$BASE_DIR/FIX_NETVPN_PROTO_DYNAMIC_MANAGER_V7C.sh" \
  "$BASE_DIR/FIX_NETVPN_MANAGER_V7D_PROTO_CLEAN.sh" \
  "$BASE_DIR/FIX_NETVPN_PROTO_CREDENTIAL_XRAY_REGISTER_V7E.sh" 2>/dev/null || true

msg "[1/4] Instalando base de protocolos + AUTH LOGIN..."
bash "$BASE_DIR/instalar_base.sh"

msg "[2/4] Aplicando manager/API V7C protocolo dinamico..."
bash "$BASE_DIR/FIX_NETVPN_PROTO_DYNAMIC_MANAGER_V7C.sh"

msg "[3/4] Limpiando/corrigiendo manager V7D..."
bash "$BASE_DIR/FIX_NETVPN_MANAGER_V7D_PROTO_CLEAN.sh"

msg "[4/4] Aplicando V7E registro automatico UUID en Xray..."
bash "$BASE_DIR/FIX_NETVPN_PROTO_CREDENTIAL_XRAY_REGISTER_V7E.sh"

# Reinicios seguros
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null || true
systemctl restart xray 2>/dev/null || true
systemctl restart netvpn-auth-status-api 2>/dev/null || true
systemctl restart netvpn-auth 2>/dev/null || true
systemctl restart svrcode-auth 2>/dev/null || true
systemctl restart netvpn-api 2>/dev/null || true
systemctl restart auth-login 2>/dev/null || true

msg "============================================================"
msg " INSTALACION COMPLETA"
msg "============================================================"
echo "Abrir manager:"
echo "  netvpn-vip"
echo
echo "Verificar API:"
echo "  curl -s http://127.0.0.1:5000/health"
echo
echo "Probar credencial Xray VIP:"
echo "  curl -s -X POST http://127.0.0.1:5000/proto/credential -H 'Content-Type: application/json' -d '{\"mode\":\"vip\",\"token\":\"TU_TOKEN\",\"hwid\":\"TU_HWID\",\"proto\":\"xray\"}'"
echo
echo "Log Xray en vivo:"
echo "  journalctl -u xray -f --no-pager"
echo
echo "Token manager: protocolo por defecto = all"
