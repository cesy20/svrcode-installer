#!/bin/bash
set -e

echo "========================================"
echo " SVRCODE - DESINSTALADOR SEGURO"
echo "========================================"
echo "Este script elimina servicios SVRCODE sin tocar OpenSSH root."
echo ""

BACKUP_DIR="/root/SVRCODE_BACKUP_BEFORE_UNINSTALL_$(date +%F_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "== Guardando respaldo básico en: $BACKUP_DIR =="
cp -a /etc/haproxy "$BACKUP_DIR/haproxy" 2>/dev/null || true
cp -a /etc/sing-box "$BACKUP_DIR/sing-box" 2>/dev/null || true
cp -a /usr/local/etc/xray "$BACKUP_DIR/xray" 2>/dev/null || true
cp -a /etc/xray "$BACKUP_DIR/xray_etc" 2>/dev/null || true
cp -a /etc/stunnel "$BACKUP_DIR/stunnel" 2>/dev/null || true
cp -a /etc/hysteria "$BACKUP_DIR/hysteria" 2>/dev/null || true
cp -a /etc/svrcode-dnstt "$BACKUP_DIR/svrcode-dnstt" 2>/dev/null || true
cp -a /etc/default/dropbear "$BACKUP_DIR/dropbear.default" 2>/dev/null || true
cp -a /root/SVRCODE_DNS_UDP_DATOS.txt "$BACKUP_DIR/" 2>/dev/null || true
cp -a /root/SVRCODE_TURBO_AUTO_020_OK.tar.gz "$BACKUP_DIR/" 2>/dev/null || true

SERVICES=(
  haproxy
  svrcode-ssh-payload
  svrcode-ssh-limitd
  svrcode-dnstt
  svrcode-udpgw-boost
  hysteria-server
  xray
  sing-box
  stunnel4
  dropbear
  nginx
)

echo "== Deteniendo servicios SVRCODE =="
for svc in "${SERVICES[@]}"; do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done

# No tocar ssh/sshd para no perder acceso a la VPS.
systemctl enable ssh >/dev/null 2>&1 || true
systemctl restart ssh >/dev/null 2>&1 || true

echo "== Eliminando unidades systemd personalizadas =="
rm -f /etc/systemd/system/svrcode-ssh-payload.service
rm -f /etc/systemd/system/svrcode-ssh-limitd.service
rm -f /etc/systemd/system/svrcode-dnstt.service
rm -f /etc/systemd/system/svrcode-udpgw-boost.service
rm -f /etc/systemd/system/hysteria-server.service
rm -rf /etc/systemd/system/dropbear.service.d
systemctl daemon-reload

echo "== Limpiando reglas NAT UDP si existen =="
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 5666 2>/dev/null || true
netfilter-persistent save >/dev/null 2>&1 || true

echo "== Eliminando comandos SVRCODE =="
rm -f /usr/local/bin/svrcode
rm -f /usr/local/bin/menu
rm -f /usr/local/bin/admin
rm -f /usr/local/bin/svrcode-test
rm -f /usr/local/bin/svrcode-udp-info
rm -f /usr/local/bin/svrcode-ssh-token
rm -f /usr/local/bin/svrcode-ssh-payload-bridge.py
rm -f /usr/local/bin/svrcode-smart80
rm -f /usr/local/bin/svrcode-fix-ssh-users
rm -f /usr/local/bin/dnstt-server

echo "== Eliminando configuraciones SVRCODE =="
rm -rf /etc/svrcode
rm -rf /etc/svrcode-dnstt
rm -rf /etc/hysteria
rm -rf /etc/sing-box
rm -rf /usr/local/etc/xray
rm -rf /etc/xray
rm -rf /etc/haproxy
rm -rf /etc/stunnel
rm -rf /root/svrcode-installer
rm -rf /root/token-manager
rm -f /root/SVRCODE_DNS_UDP_DATOS.txt

systemctl daemon-reload

echo ""
echo "========================================"
echo " DESINSTALACIÓN COMPLETADA"
echo "========================================"
echo "Respaldo guardado en: $BACKUP_DIR"
echo "OpenSSH se mantuvo activo para no perder acceso."
echo "Recomendado si vas a reinstalar limpio: reboot"
echo "========================================"
