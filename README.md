# SVRCODE FULL NETVPN MANAGER V1

Instalador único completo de SVRCODE con NETVPN Manager integrado.

Mantiene los protocolos originales y reemplaza el Token Manager viejo por el nuevo NETVPN Manager.

## Instalar

Ejecuta en la VPS como `root`:

```bash
cd /root && apt update -y && apt install -y wget curl unzip git sudo && wget -O instalar.sh https://raw.githubusercontent.com/cesy20/svrcc/main/instalar.sh && chmod +x instalar.sh && bash instalar.sh
```

## Desinstalar

Ejecuta en la VPS como `root`:

```bash
cd /root && apt update -y && apt install -y wget curl sudo && wget -O desinstalar_svrcode.sh https://raw.githubusercontent.com/cesy20/svrcc/main/desinstalar_svrcode.sh && chmod +x desinstalar_svrcode.sh && bash desinstalar_svrcode.sh
```

## Menú después de instalar

```bash
menu
```

O también:

```bash
admin
```

## NETVPN Manager

```bash
sudo svrnetvpn menu
```

Alias compatible:

```bash
sudo svrtoken menu
```
