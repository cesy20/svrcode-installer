#!/usr/bin/env bash
set -euo pipefail

DB="/etc/netvpn-vip.tokens"
MGR="/usr/local/bin/netvpn-vip"
TS="$(date +%F_%H%M%S)"

echo "==== NETVPN MANAGER V7F - proto stderr + clean tokens ===="

if [ -f "$DB" ]; then
  cp -a "$DB" "$DB.bak.v7f.$TS"
  python3 - <<'PY'
from pathlib import Path
import re

db = Path('/etc/netvpn-vip.tokens')
allowed = {'all','ssh','xray','singbox'}
rows = []
seen = {}

if db.exists():
    for raw in db.read_text(errors='ignore').splitlines():
        line = raw.replace('\x00','').strip()
        if not line or '|' not in line:
            continue
        parts = [p.strip() for p in line.split('|')]
        while len(parts) < 6:
            parts.append('')
        token, vence, hwid, estado, cliente, proto = parts[:6]
        proto = proto.lower().strip()
        estado = estado.lower().strip() or 'active'
        cliente = cliente.strip() or 'Cliente VIP'
        hwid = hwid.strip() or 'SIN-HWID'

        if not re.fullmatch(r'[0-9a-fA-F]{8,64}', token):
            continue
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', vence):
            continue
        if proto not in allowed:
            continue
        if estado not in {'active','activo','blocked','bloqueado','block','inactive','inactivo'}:
            estado = 'active'
        # Mantener HWID igual al token si la app actual lo usa así.
        row = [token, vence, hwid, estado, cliente, proto]
        seen[token] = len(rows)
        rows.append(row)

# Si hay token repetido, deja la última línea válida.
out = []
used = set()
for row in reversed(rows):
    token = row[0]
    if token in used:
        continue
    used.add(token)
    out.append(row)
out.reverse()

db.write_text('\n'.join('|'.join(r) for r in out) + ('\n' if out else ''))
print('Tokens válidos conservados:', len(out))
PY
  chmod 600 "$DB" || true
else
  echo "AVISO: No existe $DB"
fi

if [ ! -f "$MGR" ]; then
  echo "ERROR: No existe $MGR"
  exit 1
fi

cp -a "$MGR" "$MGR.bak.v7f.$TS"
python3 - <<'PY'
from pathlib import Path
import re

p = Path('/usr/local/bin/netvpn-vip')
s = p.read_text(errors='ignore')

new_func = r'''choose_proto() {
    local p
    printf "Protocolos permitidos:\n" >&2
    printf "1) all  (SSH + Xray + Sing-box)\n" >&2
    printf "2) ssh\n" >&2
    printf "3) xray\n" >&2
    printf "4) singbox\n" >&2
    printf "Elige protocolo [ENTER = all]: " >&2
    read p

    case "$p" in
        2|ssh|SSH) echo "ssh" ;;
        3|xray|XRAY) echo "xray" ;;
        4|singbox|SINGBOX|sb|SB) echo "singbox" ;;
        *) echo "all" ;;
    esac
}
'''

# Reemplaza función choose_proto completa si existe.
pat = re.compile(r'(^|\n)choose_proto\s*\(\)\s*\{.*?\n\}', re.S)
if pat.search(s):
    s = pat.sub('\n' + new_func.rstrip(), s, count=1)
    changed = True
else:
    # Inserta antes de main/menu si se puede; si no, al inicio después del shebang.
    changed = False
    insert_at = None
    for marker in ['main_menu()', 'menu_principal()', 'main()']:
        m = re.search(r'(^|\n)' + re.escape(marker), s)
        if m:
            insert_at = m.start()
            break
    if insert_at is None:
        if s.startswith('#!'):
            nl = s.find('\n') + 1
            s = s[:nl] + '\n' + new_func + '\n' + s[nl:]
        else:
            s = new_func + '\n' + s
    else:
        s = s[:insert_at] + '\n' + new_func + '\n' + s[insert_at:]

# Corrige por si existen impresiones de menú de protocolo dentro de sustitución de comandos.
# No tocamos el echo final que devuelve all/ssh/xray/singbox.
lines = []
inside = False
for line in s.splitlines():
    if re.match(r'\s*choose_proto\s*\(\)\s*\{', line):
        inside = True
    if inside:
        # Si alguna línea vieja quedó como echo/printf de textos visuales, fuerza stderr.
        if re.search(r'echo\s+["\']?(Protocolos permitidos|1\)|2\)|3\)|4\))', line) and '>&2' not in line:
            line = line + ' >&2'
        if re.search(r'printf\s+["\']?(Protocolos permitidos|1\)|2\)|3\)|4\))', line) and '>&2' not in line:
            line = line + ' >&2'
    lines.append(line)
    if inside and line.strip() == '}':
        inside = False
s = '\n'.join(lines) + '\n'

p.write_text(s)
print('Manager parcheado: choose_proto ahora muestra menú por stderr y solo devuelve proto por stdout')
PY

chmod +x "$MGR"

echo
if [ -f "$DB" ]; then
  echo "Contenido actual de $DB:"
  cat "$DB"
fi

echo
echo "Listo. Abre: netvpn-vip -> [2] Listar tokens"
