# svrcode-installer

Instalador único de **SVRCODE** con comandos ejecutables visibles para copiar desde GitHub.

## 🚀 Instalación rápida

```bash
cd /root
apt update && apt install -y wget curl unzip git
wget -O instalar.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/instalar.sh
chmod +x instalar.sh
bash instalar.sh
```

## ⚡ Instalación en una sola línea

```bash
apt update -y && apt install -y curl wget sudo && bash <(curl -fsSL https://raw.githubusercontent.com/cesy20/svrcode-installer/main/instalar.sh)
```

## 📦 Instalación clonando el repositorio

```bash
git clone https://github.com/cesy20/svrcode-installer.git
cd svrcode-installer
chmod +x instalar.sh
./instalar.sh
```

## 🧭 Abrir menú principal

```bash
menu
```

```bash
svrcode
```

## 🧩 Uso desde el menú principal

```text
[01] MAIN SSH    = clientes SSH, límite IP, renovar, bloquear, eliminar
[02] MAIN TOKEN  = menú principal Token Manager
```

> Ya no es necesario usar comandos separados para entrar al menú Token; se accede desde `menu` → `[02] MAIN TOKEN`.

## ✅ Verificar después de instalar

```bash
svrcode-test
svrcode-udp-info
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl status haproxy svrcode-ssh-payload dropbear xray sing-box hysteria-server svrcode-dnstt svrcode-udpgw-boost svrcode-ssh-limitd --no-pager -l
```

## 🔁 Reiniciar servicios principales

```bash
systemctl restart haproxy svrcode-ssh-payload dropbear ssh xray sing-box nginx stunnel4 hysteria-server svrcode-dnstt svrcode-udpgw-boost svrcode-ssh-limitd
```

## 🔎 Ver puertos activos

```bash
ss -ltnup | grep -E ':(80|8080|443|8443|53|5666|7100|7200|7300|7400|7500|7600|7789|90|2096|2097|10090|10091|10092)'
```

## 🧹 Desinstalar desde GitHub

```bash
cd /root
wget -O desinstalar_svrcode.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/desinstalar_svrcode.sh
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

## 🧹 Desinstalar si ya tienes el archivo local

```bash
cd /root
chmod +x desinstalar_svrcode.sh
bash desinstalar_svrcode.sh
```

## 🔄 Actualizar repo en VPS

```bash
cd /root/svrcode-installer && git pull
```

## 🌐 Puertos públicos para clientes

```text
NO TLS: 80 / 8080
TLS: 443 / 8443
SlowDNS: UDP 53
Hysteria2: UDP 5666
UDP Custom / Boost UDP: UDP 7100-7600
```

## 🔒 Puertos internos / backend

```text
7789  = Smart Router / SSH Payload
90    = Dropbear backend
2096  = Xray VMess backend
2097  = Xray VLess backend
10090 = Sing-box VLess backend
10091 = Sing-box VMess backend
10092 = Sing-box Trojan backend
```

> Los puertos internos no deben mostrarse como principales al cliente.
