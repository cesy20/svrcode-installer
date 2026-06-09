# SVRCODE Installer

Instalador limpio SVRCODE multipuerto con menú principal integrado.

## Instalación

```bash
cd /root
rm -rf svrcode-installer
git clone https://github.com/cesy20/svrcode-installer.git
cd svrcode-installer
chmod +x instalar.sh
bash instalar.sh
```

## Menú principal

```bash
menu
```

Dentro del menú principal:

```text
[01] MAIN SSH    = clientes SSH, límite IP, renovar, bloquear, eliminar
[02] MAIN TOKEN  = menú principal Token Manager
```

Ya no es necesario entrar al menú Token mediante comandos separados.

## Puertos públicos para clientes

```text
NO TLS: 80 / 8080
TLS:    443 / 8443
SlowDNS: UDP 53
Hysteria2: UDP 5666
UDP Custom / Boost UDP: UDP 7100-7600
```

## Puertos internos ocultos

```text
7789, 90, 2096, 2097, 10090, 10091, 10092
```

No usar esos puertos internos como principales para clientes.


## V2 fix

- Corrige instalación del NETVPN Manager cuando `/usr/local/bin/svrnetvpn` ya existe.
- Si el puerto 5000 está ocupado por una versión vieja del manager, se detiene y se actualiza ahí mismo.
- No toca HAProxy, multiport ni protocolos funcionando.
