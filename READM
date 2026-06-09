# SVRCODE FULL NETVPN MANAGER V1

Instalador único completo.

## Incluye

- Instalador original SVRCODE multiprotocolo.
- OpenSSH, Dropbear, Stunnel, HAProxy multiport, Xray, Sing-box, UDP, DNSTT, OpenVPN según el original.
- `SVRCODE NETVPN Manager` como reemplazo limpio del Token Manager viejo.
- VIP tokens, FREE on/off, online, check-user, heartbeat/disconnect, Git update FREE/VIP y Auth Gate SSH.

## No cambia

- No cambia payloads funcionando.
- No elimina multiport.
- No rompe Xray/Sing-box/UDP/DNSTT/Stunnel/HAProxy.
- No usa root ni contraseña de VPS para clientes.

## Comandos después de instalar

```bash
sudo svrnetvpn menu
sudo svrtoken menu
admin
menu
```
Instalación desde GitHub

Ejecuta este comando en tu VPS como "root":

apt update -y && apt install -y wget curl unzip && wget -O instalar_desde_github.sh https://raw.githubusercontent.com/cesy20/svrcc/main/instalar_desde_github.sh && chmod +x instalar_desde_github.sh && bash instalar_desde_github.sh

También puedes instalar con "curl":

apt update -y && apt install -y curl unzip && curl -fsSL https://raw.githubusercontent.com/cesy20/svrcc/main/instalar_desde_github.sh -o instalar_desde_github.sh && chmod +x instalar_desde_github.sh && bash instalar_desde_github.sh

Instalación manual desde el repositorio

apt update -y
apt install -y git wget curl unzip
git clone https://github.com/cesy20/svrcc.git
cd svrcc
chmod +x *.sh
bash instalar.sh

Comandos después de instalar

Menú principal:

admin

o:

menu

Manager NETVPN:

sudo svrnetvpn menu

Alias compatible del viejo token manager:

sudo svrtoken menu

Desinstalar desde GitHub

Si el repositorio tiene "desinstalar.sh", ejecuta:

wget -O desinstalar.sh https://raw.githubusercontent.com/cesy20/svrcc/main/desinstalar.sh && chmod +x desinstalar.sh && bash desinstalar.sh

O con "curl":

curl -fsSL https://raw.githubusercontent.com/cesy20/svrcc/main/desinstalar.sh -o desinstalar.sh && chmod +x desinstalar.sh && bash desinstalar.sh

Desinstalación manual

Dentro de la carpeta del instalador:

cd svrcc
chmod +x desinstalar.sh
bash desinstalar.sh

Nota importante

Este instalador mantiene intactos los protocolos principales:

OpenSSH
Dropbear
Stunnel
HAProxy multiport
Xray
Sing-box
UDP
DNSTT / SlowDNS
OpenVPN

El cambio principal es el nuevo "SVRCODE NETVPN Manager", que reemplaza el Token Manager viejo e integra:

VIP tokens
FREE on/off
usuarios online
check-user
heartbeat/disconnect
Git update FREE/VIP
Auth Gate SSH
