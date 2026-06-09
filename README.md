# SVRCODE FULL NETVPN MANAGER V1

Instalador único completo de SVRCODE con NETVPN Manager integrado.

Mantiene los protocolos originales y reemplaza el Token Manager viejo por el nuevo NETVPN Manager.

## Instalar

Ejecuta en la VPS como root:

```bash
cd /root && apt update -y && apt install -y wget curl unzip git sudo && wget -O instalar.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/instalar.sh && chmod +x instalar.sh && bash instalar.sh
```

## Desinstalar

Ejecuta en la VPS como root:

```bash
cd /root && apt update -y && apt install -y wget curl unzip git sudo && wget -O desinstalar_svrcode.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/desinstalar_svrcode.sh && chmod +x desinstalar_svrcode.sh && bash desinstalar_svrcode.sh
```

## Menú después de instalar

Menú principal:

```bash
menu
```

o:

```bash
admin
```

NETVPN Manager:

```bash
sudo svrnetvpn menu
```

Alias compatible:

```bash
sudo svrtoken menu
```

## Nota

El repo correcto es:

```text
cesy20/svrcode-installer
```

No usar:

```text
cesy20/svrcc
```

porque ese enlace da error 404 si ese repo no existe.
