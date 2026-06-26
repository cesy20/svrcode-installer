#!/usr/bin/env bash
# NETVPN VPS PATCH V7F
# Objetivo:
# - Migrar saved_hwid temporal a HWID real automáticamente.
# - Mantener compatibilidad temporal con hwid=token.
# - No tocar Xray dinámico ni app.

set -Eeuo pipefail

TOKENS_FILE="/etc/netvpn-vip.tokens"
HELPER_DIR="/usr/local/lib/netvpn"
HELPER_FILE="$HELPER_DIR/netvpn_vip_hwid_v7f.py"
CLI_FILE="/usr/local/bin/netvpn-vip-hwid-v7f"
BACKUP_DIR="/root/netvpn-backup-v7f-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/netvpn-vip-hwid-v7f.log"

say(){ echo -e "\033[1;32m[V7F]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[V7F WARN]\033[0m $*"; }
err(){ echo -e "\033[1;31m[V7F ERROR]\033[0m $*" >&2; }

require_root(){
  if [[ "${EUID}" -ne 0 ]]; then
    err "Ejecuta como root: sudo bash $0"
    exit 1
  fi
}

install_helper(){
  mkdir -p "$HELPER_DIR" "$BACKUP_DIR"
  chmod 755 "$HELPER_DIR"

  cat > "$HELPER_FILE" <<'PYEOF'
#!/usr/bin/env python3
# NETVPN VIP HWID V7F helper
# Reglas:
# 1) token inexistente / vencido / inactive => rechazo.
# 2) saved_hwid vacío, SIN-HWID o igual al token => acepta primer HWID real y lo guarda.
# 3) hwid=token sigue aceptado temporalmente para no romper pruebas actuales.
# 4) si ya hay HWID real guardado => acepta ese HWID real o, temporalmente, hwid=token.

from __future__ import annotations

import datetime as _dt
import fcntl
import json
import os
import sys
from typing import Any, Dict, List, Tuple

TOKENS_FILE = "/etc/netvpn-vip.tokens"
LOG_FILE = "/var/log/netvpn-vip-hwid-v7f.log"
NO_HWID = {"", "SIN-HWID", "sin-hwid", "NO-HWID", "no-hwid", "null", "None", "none", "0", "-"}


def _now() -> str:
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _log(msg: str) -> None:
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{_now()} {msg}\n")
    except Exception:
        pass


def _clean(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip().replace("\x00", "")


def _is_no_hwid(value: Any) -> bool:
    return _clean(value) in NO_HWID


def _is_real_hwid(token: str, hwid: str) -> bool:
    token = _clean(token)
    hwid = _clean(hwid)
    return bool(hwid) and hwid not in NO_HWID and hwid != token


def _date_ok(expiry: str) -> bool:
    expiry = _clean(expiry)
    if not expiry or expiry.lower() in {"never", "none", "null", "ilimitado", "all"}:
        return True
    # formatos aceptados: YYYY-MM-DD o YYYY/MM/DD
    expiry = expiry.replace("/", "-")[:10]
    try:
        exp = _dt.datetime.strptime(expiry, "%Y-%m-%d").date()
        return exp >= _dt.date.today()
    except Exception:
        # si el formato viejo no se entiende, no bloqueamos por fecha para no romper servicio
        return True


def _read_lines(path: str) -> List[str]:
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read().splitlines()


def _write_lines_atomic(path: str, lines: List[str]) -> None:
    tmp = f"{path}.v7f.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for line in lines:
            f.write(line.rstrip("\n") + "\n")
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o600)
    except Exception:
        pass


def _parse(line: str) -> List[str]:
    parts = line.rstrip("\n").split("|")
    while len(parts) < 6:
        parts.append("")
    return parts


def _find_token_index(lines: List[str], token: str) -> Tuple[int, List[str]]:
    token = _clean(token)
    for i, line in enumerate(lines):
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        parts = _parse(line)
        if _clean(parts[0]) == token:
            return i, parts
    return -1, []


def token_exists(token: str, path: str = TOKENS_FILE) -> bool:
    token = _clean(token)
    if not token:
        return False
    try:
        lines = _read_lines(path)
        idx, _parts = _find_token_index(lines, token)
        return idx >= 0
    except Exception:
        return False


def validate_and_migrate(token: str, incoming_hwid: str, path: str = TOKENS_FILE) -> Dict[str, Any]:
    token = _clean(token)
    incoming_hwid = _clean(incoming_hwid)

    result: Dict[str, Any] = {
        "ok": False,
        "migrated": False,
        "reason": "unknown",
        "token": token,
        "incoming_hwid": incoming_hwid,
        "saved_hwid": "",
    }

    if not token:
        result["reason"] = "empty_token"
        return result
    if not incoming_hwid:
        result["reason"] = "empty_hwid"
        return result
    if not os.path.exists(path):
        result["reason"] = "tokens_file_missing"
        return result

    lock_path = f"{path}.lock"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

    with open(lock_path, "a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        lines = _read_lines(path)
        idx, parts = _find_token_index(lines, token)
        if idx < 0:
            result["reason"] = "token_not_found"
            _log(f"FAIL token={token} hwid={incoming_hwid} reason=token_not_found")
            return result

        expiry = _clean(parts[1])
        saved_hwid = _clean(parts[2])
        status = _clean(parts[3]).lower()
        result["saved_hwid"] = saved_hwid

        if status not in {"active", "activo", "on", "1", "true", "vip"}:
            result["reason"] = f"inactive_status:{status or 'empty'}"
            _log(f"FAIL token={token} hwid={incoming_hwid} reason={result['reason']}")
            return result

        if not _date_ok(expiry):
            result["reason"] = f"expired:{expiry}"
            _log(f"FAIL token={token} hwid={incoming_hwid} reason={result['reason']}")
            return result

        # Compatibilidad temporal: la app/VPS anterior usaba TOKEN=HWID.
        # Acepta hwid=token siempre que el token esté activo, pero NO reemplaza un HWID real guardado.
        if incoming_hwid == token:
            result["ok"] = True
            result["reason"] = "accepted_legacy_hwid_equals_token"
            _log(f"OK legacy token={token} hwid=token saved_hwid={saved_hwid or '-'}")
            return result

        # Primer arranque con HWID real: si el campo viejo está vacío, SIN-HWID o igual al token, guardamos el real.
        if _is_no_hwid(saved_hwid) or saved_hwid == token:
            if _is_real_hwid(token, incoming_hwid):
                parts[2] = incoming_hwid
                lines[idx] = "|".join(parts)
                _write_lines_atomic(path, lines)
                result["ok"] = True
                result["migrated"] = True
                result["saved_hwid"] = incoming_hwid
                result["reason"] = "migrated_first_real_hwid"
                _log(f"OK migrated token={token} old_hwid={saved_hwid or '-'} new_hwid={incoming_hwid}")
                return result

        # Validación normal cuando ya existe HWID real.
        if saved_hwid == incoming_hwid:
            result["ok"] = True
            result["reason"] = "accepted_saved_hwid"
            _log(f"OK saved token={token} hwid={incoming_hwid}")
            return result

        result["reason"] = "hwid_mismatch"
        _log(f"FAIL token={token} incoming_hwid={incoming_hwid} saved_hwid={saved_hwid} reason=hwid_mismatch")
        return result


def _candidate_tokens_from_scope(scope: Dict[str, Any]) -> List[str]:
    candidates: List[str] = []
    # Prioriza variables cuyo nombre realmente parece token.
    for name, val in scope.items():
        lname = str(name).lower()
        if "token" in lname or lname in {"tk", "vip"}:
            sval = _clean(val)
            if sval and sval not in candidates:
                candidates.append(sval)
    # Fallback: prueba strings locales de tamaño razonable.
    for _name, val in scope.items():
        sval = _clean(val)
        if 8 <= len(sval) <= 128 and sval not in candidates:
            candidates.append(sval)
    return candidates


def netvpn_vip_hwid_v7f_accept_locals(scope: Dict[str, Any], value_a: Any, value_b: Any) -> bool:
    """Helper para parchar condiciones antiguas tipo: if saved_hwid != hwid:

    No depende del orden de variables. Recibe los dos valores comparados, busca el token VIP
    en locals(), prueba primero el valor que parece HWID real y luego mantiene compatibilidad
    con hwid=token. Así sirve tanto para:
      if saved_hwid != hwid:
    como para:
      if hwid != saved_hwid:
    """
    a = _clean(value_a)
    b = _clean(value_b)

    # Si ya coincide, no hace falta tocar nada.
    if a and b and a == b:
        return True

    for token in _candidate_tokens_from_scope(scope):
        if not token_exists(token):
            continue

        # Primero prueba el posible HWID real para que se haga la migración automática.
        incoming_candidates = []
        for val in (a, b):
            if _is_real_hwid(token, val) and val not in incoming_candidates:
                incoming_candidates.append(val)
        # Después prueba valores legacy como hwid=token.
        for val in (a, b):
            if val and val not in incoming_candidates:
                incoming_candidates.append(val)

        for incoming in incoming_candidates:
            res = validate_and_migrate(token, incoming)
            if res.get("ok"):
                return True
    return False


def main(argv: List[str]) -> int:
    if len(argv) < 3:
        print("Uso: netvpn-vip-hwid-v7f TOKEN HWID [--json]", file=sys.stderr)
        return 2
    token = argv[1]
    hwid = argv[2]
    res = validate_and_migrate(token, hwid)
    if "--json" in argv:
        print(json.dumps(res, ensure_ascii=False, sort_keys=True))
    else:
        status = "OK" if res.get("ok") else "FAIL"
        migrated = " migrated=1" if res.get("migrated") else " migrated=0"
        print(f"{status} reason={res.get('reason')}{migrated} saved_hwid={res.get('saved_hwid','')}")
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
PYEOF

  chmod 755 "$HELPER_FILE"

  cat > "$CLI_FILE" <<EOFCLI
#!/usr/bin/env bash
PYTHONPATH="$HELPER_DIR:\${PYTHONPATH:-}" exec python3 "$HELPER_FILE" "\$@"
EOFCLI
  chmod 755 "$CLI_FILE"

  python3 -m py_compile "$HELPER_FILE"
  say "Helper instalado: $HELPER_FILE"
  say "CLI instalado: $CLI_FILE"
}

backup_tokens(){
  mkdir -p "$BACKUP_DIR"
  if [[ -f "$TOKENS_FILE" ]]; then
    cp -a "$TOKENS_FILE" "$BACKUP_DIR/netvpn-vip.tokens.bak"
    chmod 600 "$TOKENS_FILE" || true
    say "Backup tokens: $BACKUP_DIR/netvpn-vip.tokens.bak"
  else
    warn "No existe $TOKENS_FILE todavía. El helper queda instalado igual."
  fi
}

patch_python_file(){
  local f="$1"
  python3 - "$f" "$BACKUP_DIR" "$HELPER_DIR" <<'PYEOF'
from __future__ import annotations
import os
import re
import shutil
import sys

path, backup_dir, helper_dir = sys.argv[1:4]
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        src = fh.read()
except Exception:
    print("SKIP read_error", path)
    raise SystemExit(0)

if "netvpn_vip_hwid_v7f" in src:
    print("SKIP already_patched", path)
    raise SystemExit(0)

low = src.lower()
if "/etc/netvpn-vip.tokens" not in src and "netvpn-vip.tokens" not in src:
    print("SKIP no_tokens", path)
    raise SystemExit(0)
if "hwid" not in low and "device" not in low:
    print("SKIP no_hwid", path)
    raise SystemExit(0)
if "vip" not in low:
    print("SKIP no_vip", path)
    raise SystemExit(0)

lines = src.splitlines(True)
changed = False
patched_lines = []

# Inserta import después de imports iniciales.
inserted_import = False
last_import_idx = -1
for i, line in enumerate(lines[:80]):
    stripped = line.strip()
    if stripped.startswith("import ") or stripped.startswith("from "):
        last_import_idx = i
if last_import_idx >= 0:
    lines.insert(last_import_idx + 1, f"\n# NETVPN V7F HWID migration\nimport sys as _netvpn_v7f_sys\n_netvpn_v7f_sys.path.insert(0, {helper_dir!r})\nfrom netvpn_vip_hwid_v7f import netvpn_vip_hwid_v7f_accept_locals\n# END NETVPN V7F\n")
    inserted_import = True
else:
    lines.insert(0, f"# NETVPN V7F HWID migration\nimport sys as _netvpn_v7f_sys\n_netvpn_v7f_sys.path.insert(0, {helper_dir!r})\nfrom netvpn_vip_hwid_v7f import netvpn_vip_hwid_v7f_accept_locals\n# END NETVPN V7F\n\n")
    inserted_import = True

# Patrones conservadores: solo cambia comparaciones != entre variables donde ambos nombres parecen HWID/device.
# Ejemplos que soporta:
#   if saved_hwid != hwid:
#   if hwid != saved_hwid:
#   if stored_device != device_id:
#   if saved_hwid and saved_hwid != hwid:
# El helper busca el token real en locals() y aplica la regla V7F.
pat_and = re.compile(r"^(?P<ind>\s*)if\s+(?P<a>[A-Za-z_]\w*)\s+and\s+(?P=a)\s*!=\s*(?P<b>[A-Za-z_]\w*)\s*:\s*(?P<c>#.*)?$")
pat_ne = re.compile(r"^(?P<ind>\s*)if\s+(?P<a>[A-Za-z_]\w*)\s*!=\s*(?P<b>[A-Za-z_]\w*)\s*:\s*(?P<c>#.*)?$")

def is_hwid_name(name: str) -> bool:
    n = name.lower()
    return "hwid" in n or "device" in n or "imei" in n or "android" in n

def replacement(ind: str, a: str, b: str, comment: str = "") -> str:
    c = (" " + comment.strip()) if comment else ""
    return f"{ind}if not (str({a}).strip() == str({b}).strip() or netvpn_vip_hwid_v7f_accept_locals(locals(), {a}, {b})):{c}\n"

for line in lines:
    raw = line.rstrip("\n")
    m = pat_and.match(raw)
    if m and is_hwid_name(m.group("a")) and is_hwid_name(m.group("b")):
        patched_lines.append(replacement(m.group("ind"), m.group("a"), m.group("b"), m.group("c") or ""))
        changed = True
        continue
    m = pat_ne.match(raw)
    if m and is_hwid_name(m.group("a")) and is_hwid_name(m.group("b")):
        patched_lines.append(replacement(m.group("ind"), m.group("a"), m.group("b"), m.group("c") or ""))
        changed = True
        continue
    patched_lines.append(line)

if not changed:
    # Quita import si no se pudo aplicar ningún cambio útil.
    print("SKIP no_strict_hwid_condition", path)
    raise SystemExit(0)

os.makedirs(backup_dir, exist_ok=True)
base = os.path.basename(path).replace("/", "_")
backup_path = os.path.join(backup_dir, base + ".bak")
shutil.copy2(path, backup_path)
with open(path, "w", encoding="utf-8") as fh:
    fh.write("".join(patched_lines))

# Comprueba sintaxis si es Python.
import py_compile
try:
    py_compile.compile(path, doraise=True)
except Exception as e:
    shutil.copy2(backup_path, path)
    print("FAIL syntax_rollback", path, str(e))
    raise SystemExit(0)

print("PATCHED", path, "backup=", backup_path)
PYEOF
}

find_candidates(){
  local roots=(/usr/local/bin /usr/local/sbin /opt /root /etc/systemd/system)
  for d in "${roots[@]}"; do
    [[ -d "$d" ]] || continue
    find "$d" -type f -size -1024k \( -name '*.py' -o -name '*gate*' -o -name '*ssh*' -o -name '*netvpn*' \) \
      -not -path '*/__pycache__/*' 2>/dev/null || true
  done | sort -u
}

patch_gate_files(){
  local patched_count=0
  local candidate
  say "Buscando gate/validador VIP que use $TOKENS_FILE..."
  while IFS= read -r candidate; do
    [[ -f "$candidate" ]] || continue
    if grep -Iq . "$candidate" && grep -qiE 'netvpn-vip\.tokens|/etc/netvpn-vip\.tokens' "$candidate" && grep -qiE 'hwid|device|imei|android' "$candidate" && grep -qi 'vip' "$candidate"; then
      local out
      out="$(patch_python_file "$candidate" || true)"
      echo "$out"
      if echo "$out" | grep -q '^PATCHED '; then
        patched_count=$((patched_count+1))
      fi
    fi
  done < <(find_candidates)

  if [[ "$patched_count" -eq 0 ]]; then
    warn "No pude modificar automáticamente el archivo SSH-GATE."
    warn "El helper quedó instalado. Busca el archivo con: grep -Rni 'netvpn-vip.tokens\|saved_hwid\|hwid' /usr/local/bin /opt /root 2>/dev/null"
    warn "Luego reemplaza el chequeo estricto de HWID por el helper V7F."
  else
    say "Archivos gate parchados: $patched_count"
  fi
}

restart_related_services(){
  say "Intentando reiniciar servicios NETVPN/SSH-GATE relacionados..."
  systemctl daemon-reload >/dev/null 2>&1 || true

  local restarted=0
  local svc
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    local unit_text
    unit_text="$(systemctl cat "$svc" 2>/dev/null || true)"
    if echo "$unit_text" | grep -qiE 'netvpn|ssh.*gate|asyncssh|vip.tokens|netvpn-vip'; then
      if systemctl restart "$svc" >/dev/null 2>&1; then
        say "Reiniciado: $svc"
        restarted=$((restarted+1))
      fi
    fi
  done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Ei 'netvpn|gate|ssh|svr|vpn' || true)

  if [[ "$restarted" -eq 0 ]]; then
    warn "No detecté servicio para reiniciar automáticamente. Reinicia manualmente el servicio SSH-GATE si aplica."
  fi
}

show_current_token_state(){
  if [[ -f "$TOKENS_FILE" ]]; then
    say "Estado actual de tokens VIP:"
    awk -F'|' 'BEGIN{printf "%-20s %-12s %-24s %-10s %-12s %-8s\n","TOKEN","FECHA","SAVED_HWID","STATUS","NOMBRE","LIMITE"} /^[[:space:]]*#/ || NF==0 {next} {printf "%-20s %-12s %-24s %-10s %-12s %-8s\n",$1,$2,$3,$4,$5,$6}' "$TOKENS_FILE" || true
  fi
}

self_test_with_existing_token(){
  if [[ ! -f "$TOKENS_FILE" ]]; then
    return 0
  fi
  local token
  token="$(awk -F'|' 'NF>=4 && tolower($4) ~ /active|activo|on|1|true/ {print $1; exit}' "$TOKENS_FILE" || true)"
  if [[ -n "$token" ]]; then
    say "Prueba compatibilidad hwid=token con token: $token"
    "$CLI_FILE" "$token" "$token" --json || true
    say "Para probar migración real usa: $CLI_FILE $token HWID_REAL_DEL_CELULAR --json"
  fi
}

main(){
  require_root
  say "Aplicando FIX NETVPN VIP HWID MIGRATE V7F"
  backup_tokens
  install_helper
  patch_gate_files
  restart_related_services
  show_current_token_state
  self_test_with_existing_token
  say "Listo. Logs V7F: $LOG_FILE"
  say "Regla activa: si saved_hwid está vacío/SIN-HWID/token, el primer HWID real se guarda; hwid=token sigue aceptado temporalmente."
}

main "$@"
