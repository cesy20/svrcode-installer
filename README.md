# SVRCODE FULL NETVPN MANAGER V2

Instalador completo con protocolos originales intactos y NETVPN Manager corregido.

## Instalar desde ZIP

```bash
cd /root
unzip -o SVRCODE_FULL_NETVPN_MANAGER_V2.zip
cd svrcode-installer-main
chmod +x instalar.sh
sudo bash instalar.sh
```

## Instalar desde GitHub

```bash
cd /root && apt update -y && apt install -y wget curl unzip git sudo && wget -O instalar.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/instalar.sh && chmod +x instalar.sh && bash instalar.sh
```

## Desinstalar

```bash
cd /root && apt update -y && apt install -y wget curl unzip git sudo && wget -O desinstalar_svrcode.sh https://raw.githubusercontent.com/cesy20/svrcode-installer/main/desinstalar_svrcode.sh && chmod +x desinstalar_svrcode.sh && bash desinstalar_svrcode.sh
```

## V2 corrige

- NETVPN Manager ya no falla si `/usr/local/bin/svrnetvpn` ya existe.
- Si el puerto 5000 está ocupado por el manager viejo/nuevo, lo reinicia y actualiza ahí mismo.
- No toca HAProxy, multiport ni protocolos funcionando.

## Menús

```bash
menu
admin
sudo svrnetvpn menu
sudo svrtoken menu
```
