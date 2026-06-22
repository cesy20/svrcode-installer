#!/usr/bin/env bash
set -euo pipefail

MANAGER="/usr/local/bin/netvpn-vip"
DB="/etc/netvpn-vip.tokens"
TS="$(date +%F_%H%M%S)"

[ -f "$MANAGER" ] || { echo "ERROR: no existe $MANAGER"; exit 1; }
mkdir -p /etc
[ -f "$DB" ] || touch "$DB"

cp -a "$MANAGER" "$MANAGER.bak_v7d_$TS" || true
cp -a "$DB" "$DB.bak_v7d_$TS" || true

# 1) Limpiar caracteres nulos y filas basura creadas por el menú de protocolo capturado
python3 - <<'PY_CLEAN'
from pathlib import Path
import re, datetime, os
p=Path('/etc/netvpn-vip.tokens')
rows=[]
if p.exists():
    raw=p.read_text(errors='ignore').replace('\x00','')
    for line in raw.splitlines():
        line=line.strip()
        if not line or line.startswith('#'):
            continue
        token=line.split('|',1)[0].strip()
        low=token.lower().strip()
        # filas basura del bug V7C: "Protocolos permitidos", "1) all", "2) ssh", "3) xray", "4) singbox", "all" suelto
        if low.startswith('protocolos permitidos'):
            continue
        if re.match(r'^[1-4]\)\s*(all|ssh|xray|singbox|sing)', low):
            continue
        if low in {'all','ssh','xray','singbox','sing-box'} and '|' not in line:
            continue
        parts=[x.strip() for x in line.split('|')]
        while len(parts)<6:
            parts.append('')
        # normalizar fecha/estado/nombre/proto sin destruir token real
        if not parts[1]:
            parts[1]=(datetime.date.today()+datetime.timedelta(days=30)).isoformat()
        if not parts[3]:
            parts[3]='active'
        if not parts[4]:
            parts[4]='Cliente VIP'
        proto=(parts[5] or 'all').lower().strip()
        if proto in {'v2ray','vmess','vless'}:
            proto='xray'
        elif proto in {'sing','sing-box'}:
            proto='singbox'
        elif proto not in {'all','ssh','xray','singbox'}:
            proto='all'
        parts[5]=proto
        rows.append('|'.join(parts[:6]))
p.write_text('\n'.join(rows)+('\n' if rows else ''), encoding='utf-8')
os.chmod(str(p), 0o600)
print(f"DB limpio: {len(rows)} token(s) válido(s). Backup guardado en /etc/netvpn-vip.tokens.bak_v7d_*")
PY_CLEAN

# 2) Corregir ask_proto(): el menú debe imprimirse en pantalla, pero SOLO el valor final va a stdout.
python3 - <<'PY_PATCH'
from pathlib import Path
import re
m=Path('/usr/local/bin/netvpn-vip')
s=m.read_text(errors='ignore')
new_func=r'''ask_proto(){
  {
    echo "Protocolos permitidos:"
    echo "1) all     (SSH + Xray + Sing-box)"
    echo "2) ssh"
    echo "3) xray"
    echo "4) singbox"
    printf "Elige protocolo [ENTER=all]: "
  } > /dev/tty
  IFS= read -r p < /dev/tty || p=""
  case "$p" in
    2|ssh|SSH) echo ssh ;;
    3|xray|XRAY|v2ray|vmess|vless) echo xray ;;
    4|sing|singbox|sing-box|SINGBOX) echo singbox ;;
    *) echo all ;;
  esac
}'''
pat=re.compile(r'ask_proto\(\)\{.*?\n\}\n\nadd_token\(\)\{', re.S)
if not pat.search(s):
    raise SystemExit('ERROR: no pude ubicar ask_proto() en /usr/local/bin/netvpn-vip')
s=pat.sub(new_func+'\n\nadd_token(){', s)
s=s.replace('MANAGER V7C PROTO','MANAGER V7D PROTO')
m.write_text(s)
print('Manager corregido: ask_proto ya no ensucia la base de tokens.')
PY_PATCH

chmod +x "$MANAGER"

# 3) Reiniciar API si existe
if systemctl list-unit-files 2>/dev/null | grep -q '^netvpn-auth-status-api.service'; then
  systemctl daemon-reload || true
  systemctl restart netvpn-auth-status-api.service || true
fi

echo ""
echo "OK ✅ NETVPN manager V7D corregido."
echo "Ahora ejecuta: netvpn-vip"
echo "Luego opción [2] Listar: debe quedar solo el/los tokens reales."
