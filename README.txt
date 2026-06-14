NETVPN FULL UNICO COMPLETO V5

CAMBIO PRINCIPAL:
- instalar.sh ya NO muestra menu.
- Instala todo en una sola corrida: protocolos base + NETVPN AUTH LOGIN + netvpn-vip + API 5000.
- Pregunta el AUTH/dominio real de esa VPS durante la instalacion.
- Incluye el instalador de protocolos embebido dentro de instalar.sh y tambien como ZIP externo.

INSTALAR EN VPS LIMPIA:
cd /root
apt update -y && apt install -y unzip curl wget sudo
unzip NETVPN_FULL_UNICO_COMPLETO_V5_AUTO_FULL_NO_MENU.zip
cd NETVPN_FULL_UNICO_COMPLETO_V5_AUTO_FULL_NO_MENU
chmod +x instalar.sh
bash instalar.sh

Cuando pregunte AUTH, escribe el dominio/auth de ESA VPS.
Ese mismo AUTH debe ir en el GEN del servidor.

COMANDOS DESPUES:
netvpn-vip menu
netvpn-vip free-off
netvpn-vip free-on
netvpn-vip add TOKEN 15 "Cliente"
netvpn-vip list

REVERTIR:
bash /root/REVERT_NETVPN_AUTH_LOGIN.sh
