# SVRCODE FULL NETVPN MANAGER V1

Instalador único completo de **SVRCODE** con protocolos multipuerto y nuevo **SVRCODE NETVPN Manager** integrado.

Este instalador mantiene los comandos originales y agrega el nuevo manager limpio como reemplazo del Token Manager viejo.

---

## Incluye

- Instalador original SVRCODE multiprotocolo.
- OpenSSH, Dropbear, Stunnel, HAProxy multiport, Xray, Sing-box, UDP, DNSTT, OpenVPN según el original.
- `SVRCODE NETVPN Manager` como reemplazo limpio del Token Manager viejo.
- VIP tokens.
- FREE on/off.
- Usuarios online.
- Check-user.
- Heartbeat/disconnect.
- Git update FREE/VIP.
- Auth Gate SSH para app sin usuario y contraseña fija.

---

## No cambia

- No cambia payloads funcionando.
- No elimina multiport.
- No rompe Xray/Sing-box/UDP/DNSTT/Stunnel/HAProxy.
- No usa root ni contraseña de VPS para clientes.
- No obliga a mandar `ServerUser` ni `ServerPass` desde el GEN.

---

# Instalación rápida desde GitHub

Ejecuta en la VPS como `root`:

```bash
cd /root
apt update && apt install -y wget curl unzip git
wget -O instalar.sh https://raw.githubusercontent.com/cesy20/svrcc/main/instalar.sh
chmod +x instalar.sh
bash instalar.sh
```

---

# Instalación en una sola línea

```bash
apt update -y && apt install -y curl wget sudo unzip git && bash <(curl -fsSL https://raw.githubusercontent.com/cesy20/svrcc/main/instalar.sh)
```

---

# Instalación usando instalar_desde_github.sh

```bash
cd /root
apt update -y && apt install -y wget curl unzip git
wget -O instalar_desde_github.sh https://raw.githubusercontent.com/cesy20/svrcc/main/instalar_desde_github.sh
chmod +x instalar_desde_github.sh
bash instalar_desde_github.sh
```

También con `curl`:

```bash
cd /root
apt update -y && apt install -y curl unzip git
curl -fsSL https://raw.githubusercontent.com/cesy20/svrcc/main/instalar_desde_github.sh -o instalar_desde_github.sh
chmod +x instalar_desde_github.sh
bash instalar_desde_github.sh
```

---

# Instalación clonando el repositorio

```bash
cd /root
apt update -y && apt install -y git wget curl unzip
git clone https://github.com/cesy20/svrcc.git
cd svrcc
chmod +x *.sh
bash instalar.sh
```

---

# Instalación manual si subiste el ZIP

```bash
cd /root
unzip -o SVRCODE_FULL_NETVPN_MANAGER_V1.zip
cd svrcode-installer-main
chmod +x *.sh
sudo bash instalar.sh
```

En una sola línea:

```bash
cd /root && unzip -o SVRCODE_FULL_NETVPN_MANAGER_V1.zip && cd svrcode-installer-main && chmod +x *.sh && sudo bash instalar.sh
```

---

# Abrir menú principal

```bash
menu
```

```bash
admin
```

```bash
svrcode
```

---

# Uso desde el menú principal

```text
[01] MAIN SSH    = clientes SSH, límite IP, renovar, bloquear, eliminar
[02] MAIN TOKEN  = SVRCODE NETVPN Manager nuevo
```

También puedes entrar directo al nuevo manager con:

```bash
sudo svrnetvpn menu
```

Alias compatible del viejo Token Manager:

```bash
sudo svrtoken menu
```

---

# Verificar después de instalar

```bash
svrcode-test
svrcode-udp-info
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl status haproxy svrcode-ssh-payload dropbear xray sing-box hysteria-server svrcode-dnstt svrcode-udpgw-boost svrcode-ssh-limitd --no-pager -l
```

Ver estado del nuevo NETVPN Manager:

```bash
sudo svrnetvpn status
```

Ver configuración API/Gate:

```bash
sudo svrnetvpn api-config
```

---

# Reiniciar servicios principales

```bash
systemctl restart haproxy svrcode-ssh-payload dropbear ssh xray sing-box nginx stunnel4 hysteria-server svrcode-dnstt svrcode-udpgw-boost svrcode-ssh-limitd
```

Reiniciar el nuevo manager:

```bash
systemctl restart svrcode-netvpn-api
```

---

# Ver puertos activos

```bash
ss -ltnup | grep -E ':(80|8080|443|8443|53|5666|7100|7200|7300|7400|7500|7600|7789|90|2096|2097|10090|10091|10092|5000|22022)'
```

---

# Comandos del nuevo NETVPN Manager

Abrir menú:

```bash
sudo svrnetvpn menu
```

Ver estado:

```bash
sudo svrnetvpn status
```

Ver API/configuración:

```bash
sudo svrnetvpn api-config
```

Ver logs:

```bash
sudo svrnetvpn logs 100
```

Ver logs de autenticación:

```bash
sudo svrnetvpn auth-logs 100
```

---

# Crear token VIP

```bash
sudo svrnetvpn add cliente1 all 30 1
```

Formato:

```bash
sudo svrnetvpn add NOMBRE PROTO DIAS MAX_DISPOSITIVOS
```

Ejemplos:

```bash
sudo svrnetvpn add juan all 30 1
sudo svrnetvpn add maria ssh 15 1
sudo svrnetvpn add clientevip singbox 30 1
```

Con token personalizado:

```bash
sudo svrnetvpn add clientevip all 30 1 MITOKEN123
```

---

# Ver tokens y usuarios online

Listar tokens:

```bash
sudo svrnetvpn list
```

Ver usuarios online:

```bash
sudo svrnetvpn online
```

Verificar usuario:

```bash
sudo svrnetvpn check-user TOKEN HWID
```

---

# FREE

Activar FREE:

```bash
sudo svrnetvpn free on
```

Desactivar FREE:

```bash
sudo svrnetvpn free off
```

Ver estado FREE:

```bash
sudo svrnetvpn free status
```

---

# Git update FREE/VIP

Configurar Git:

```bash
sudo svrnetvpn git-config usuario/REPO main FreeMode/Config.json VipMode/Config.mvgl.json TOKEN_GITHUB_OPCIONAL
```

Ejemplo:

```bash
sudo svrnetvpn git-config cesy20/svrcc main FreeMode/Config.json VipMode/Config.mvgl.json
```

Sincronizar Git:

```bash
sudo svrnetvpn git-sync
```

---

# Desinstalar desde GitHub

```bash
cd /root
wget -O desinstalar_svrcode.sh https://raw.githubusercontent.com/cesy20/svrcc/main/desinstalar_svrcode.sh
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

También con `curl`:

```bash
cd /root
curl -fsSL https://raw.githubusercontent.com/cesy20/svrcc/main/desinstalar_svrcode.sh -o desinstalar_svrcode.sh
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

---

# Desinstalar si ya tienes el archivo local

```bash
cd /root
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

Si estás dentro del repositorio:

```bash
cd /root/svrcc
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

---

# Desinstalar solo NETVPN Manager sin borrar datos

```bash
sudo svrnetvpn uninstall
```

---

# Actualizar repositorio en VPS

```bash
cd /root/svrcc && git pull
```

Si lo instalaste con otro nombre de carpeta:

```bash
cd /root/svrcode-installer-main && git pull
```

---

# Puertos públicos para clientes

```text
NO TLS: 80 / 8080
TLS: 443 / 8443
SlowDNS: UDP 53
Hysteria2: UDP 5666
UDP Custom / Boost UDP: UDP 7100-7600
```

---

# Puertos internos / backend

```text
7789  = Smart Router / SSH Payload
90    = Dropbear backend
2096  = Xray VMess backend
2097  = Xray VLess backend
10090 = Sing-box VLess backend
10091 = Sing-box VMess backend
10092 = Sing-box Trojan backend
22022 = OpenSSH Auth Gate interno
5000  = API NETVPN Manager
```

Los puertos internos no deben mostrarse como principales al cliente.

---

# Formato para la app nueva

Usuario SSH interno:

```text
svrgate
```

Ticket FREE como contraseña:

```text
free:<auth>:<HWID>[:proto]
```

Ticket VIP como contraseña:

```text
vip:<auth>:<TOKEN>:<HWID>[:proto]
```

El GEN no debe mandar:

```text
ServerUser
ServerPass
```

La APK nueva no debe llevar:

```text
ADMIN_KEY
APP_KEY fijo
contraseña root
contraseña real de la VPS
```

---

# Recomendación final

Usa:

```bash
menu
```

para administración general.

Usa:

```bash
sudo svrnetvpn menu
```

para administrar VIP, FREE, online, Git y Auth Gate.

El alias:

```bash
sudo svrtoken menu
```

queda compatible, pero ahora apunta al nuevo NETVPN Manager.
