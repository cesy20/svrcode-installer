#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NETVPN AUTH LOGIN + PROTOCOLOS + TOKEN MANAGER
# Instalador unico para VPS
# V4: AUTH preguntado por VPS, sin API token vieja, FREE ON/OFF,
#     API 5000 se actualiza/reemplaza si ya estaba ocupada.
# ============================================================

INSTALL_MODE="${INSTALL_MODE:-menu}"   # menu | full | auth | protocolos
AUTH_MAIN="${AUTH_MAIN:-}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTO_ZIP="$BASE_DIR/svrcode-installerFULL_original.zip"
WORK_PROTO="/root/svrcode-installerFULL"

BRIDGE="/opt/svrcode/ssh_payload_bridge.py"
PAM_SCRIPT="/usr/local/bin/netvpn-auth-login-pam.py"
CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"
STATUS_API="/usr/local/bin/netvpn-auth-status-api.py"
TOKEN_MANAGER="/usr/local/bin/netvpn-vip"
BACKUP_DIR="/root/netvpn_auth_login_backup_$(date +%F_%H%M%S)"

C0='\033[0m'; C1='\033[1;32m'; C2='\033[1;36m'; C3='\033[1;33m'; C4='\033[1;31m'
msg(){ echo -e "${C1}$*${C0}"; }
info(){ echo -e "${C2}$*${C0}"; }
warn(){ echo -e "${C3}$*${C0}"; }
err(){ echo -e "${C4}$*${C0}"; }

require_root(){
  if [ "${EUID:-$(id -u)}" != "0" ]; then
    err "ERROR: ejecuta como root"
    exit 1
  fi
}

clean_auth(){
  local a="${1:-}"
  a="${a#http://}"; a="${a#https://}"; a="${a%%/*}"
  echo "$a"
}

detected_auth(){
  grep -E '^AUTH_LIST=' "$CONF" 2>/dev/null | head -1 | cut -d= -f2- | awk '{print $1}' || true
}

ask_auth_main(){
  local old_auth
  old_auth="$(detected_auth)"

  if [ -n "${AUTH_MAIN:-}" ]; then
    AUTH_MAIN="$(clean_auth "$AUTH_MAIN")"
    if [ -z "$AUTH_MAIN" ]; then
      err "ERROR: AUTH_MAIN vacio"
      exit 1
    fi
    return 0
  fi

  echo
  echo "============================================================"
  echo " CONFIGURAR DOMINIO / AUTH DE ESTA VPS"
  echo "============================================================"
  echo "Este AUTH debe ser el mismo que pondras en el GEN/servidor."
  echo "Ejemplo: api.midominio.com"
  if [ -n "$old_auth" ]; then
    echo "AUTH detectado anterior: $old_auth"
  fi
  echo

  while true; do
    if [ -n "$old_auth" ]; then
      read -rp "Escribe AUTH de esta VPS [ENTER mantiene $old_auth]: " AUTH_MAIN
      [ -z "${AUTH_MAIN:-}" ] && AUTH_MAIN="$old_auth"
    else
      read -rp "Escribe AUTH de esta VPS: " AUTH_MAIN
    fi
    AUTH_MAIN="$(clean_auth "${AUTH_MAIN:-}")"
    if [ -n "$AUTH_MAIN" ]; then
      break
    fi
    echo "No puede estar vacio."
  done
}

install_protocolos_base(){
  clear || true
  echo "============================================================"
  echo " INSTALAR PROTOCOLOS BASE SVRCODE"
  echo "============================================================"
  echo

  if [ ! -f "$PROTO_ZIP" ]; then
    err "ERROR: no existe $PROTO_ZIP"
    exit 1
  fi

  apt-get update -y
  apt-get install -y unzip curl wget python3 openssh-server ca-certificates sudo

  rm -rf "$WORK_PROTO"
  mkdir -p "$WORK_PROTO"
  unzip -o "$PROTO_ZIP" -d "$WORK_PROTO"

  INSTALLER="$(find "$WORK_PROTO" -type f \( -name 'instalar.sh' -o -name 'install.sh' \) | head -1 || true)"
  if [ -z "$INSTALLER" ]; then
    err "ERROR: no encontre instalar.sh/install.sh dentro del zip"
    find "$WORK_PROTO" -maxdepth 4 -type f | sed -n '1,80p'
    exit 1
  fi

  chmod +x "$INSTALLER"
  msg "Ejecutando instalador base: $INSTALLER"
  bash "$INSTALLER"

  msg "=== PROTOCOLOS BASE INSTALADOS ==="
}

stop_old_apis_free_5000(){
  msg "Apagando API token vieja y liberando puerto 5000..."
  systemctl disable --now svrcode-token-api.service 2>/dev/null || true
  systemctl disable --now svrcode-api-front-proxy.service 2>/dev/null || true
  systemctl disable --now svrcode-netvpn-api.service 2>/dev/null || true
  systemctl disable --now svrcode-ssh-dynamic-api.service 2>/dev/null || true
  systemctl stop netvpn-auth-status-api.service 2>/dev/null || true

  pkill -f "svrcode-token-api" 2>/dev/null || true
  pkill -f "api-front-proxy" 2>/dev/null || true
  pkill -f "svrcode.*dynamic.*api" 2>/dev/null || true

  local pids
  pids="$(ss -ltnp 2>/dev/null | awk '/:5000/{print $NF}' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u || true)"
  for pid in $pids; do
    local cmd
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    warn "Puerto 5000 ocupado por pid=$pid $cmd"
    kill -9 "$pid" 2>/dev/null || true
  done
}

write_pam_validator(){
  msg "Instalando validador PAM AUTH LOGIN..."
  cat > "$PAM_SCRIPT" <<'PY'
#!/usr/bin/env python3
import os, sys, hashlib, datetime

CONF = "/etc/netvpn-auth-login.conf"

def read_conf():
    d = {}
    try:
        with open(CONF) as f:
            for line in f:
                line=line.strip()
                if line and "=" in line and not line.startswith("#"):
                    k,v=line.split("=",1)
                    d[k.strip()] = v.strip()
    except Exception:
        pass
    return d

def log(msg):
    cfg=read_conf(); path=cfg.get("LOG","/var/log/netvpn-auth-login.log")
    try:
        with open(path,"a") as f:
            now=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{now} {msg}\n")
    except Exception:
        pass

def active_flag(v):
    return str(v).strip().lower() in ("1","true","active","activo","on","yes","si")

def expected_user(auth):
    return "nvp_" + hashlib.sha256(auth.encode()).hexdigest()[:12]

def valid_auth(auth,cfg):
    auths=cfg.get("AUTH_LIST","")
    arr=[x.strip() for x in auths.replace(","," ").split() if x.strip()]
    return auth in arr

def rewrite_vip_db(db, rows):
    try:
        with open(db,"w",encoding="utf-8") as f:
            for r in rows:
                f.write("|".join(r)+"\n")
        os.chmod(db,0o600)
    except Exception:
        pass

def vip_ok(token, hwid, cfg):
    db=cfg.get("VIP_DB","/etc/netvpn-vip.tokens")
    today=datetime.date.today()
    rows=[]; found_index=None; found=None
    try:
        with open(db, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line=line.strip()
                if not line or line.startswith("#"):
                    continue
                p=[x.strip() for x in line.split("|")]
                while len(p)<5: p.append("")
                if p[0] == token and found is None:
                    found_index=len(rows); found=p
                rows.append(p[:5])
    except Exception:
        return False, "vip_db_error"

    if found is None:
        return False, "vip_not_found"

    t, exp, saved_hwid, st, name = found
    if not active_flag(st):
        return False, "vip_inactive"
    try:
        if datetime.date.fromisoformat(exp[:10]) < today:
            return False, "vip_expired"
    except Exception:
        return False, "vip_bad_expire"

    # Auto bind: si el token fue creado sin HWID, se amarra al primer HWID real.
    if not saved_hwid:
        if not hwid:
            return False, "no_hwid"
        rows[found_index][2] = hwid
        rewrite_vip_db(db, rows)
        return True, "active_bound"

    if saved_hwid != "*" and saved_hwid != hwid:
        return False, "hwid_mismatch"

    return True, "active"

def main():
    cfg=read_conf()
    user=os.environ.get("PAM_USER","")
    password=sys.stdin.read().strip("\r\n")

    if not user.startswith("nvp_"):
        sys.exit(1)

    parts=password.split("|")
    if len(parts)<5 or parts[0] != "NVP1":
        log(f"REJECT user={user} reason=bad_format")
        sys.exit(1)

    mode=parts[1].strip().lower()
    auth=parts[2].strip()

    if not valid_auth(auth,cfg):
        log(f"REJECT user={user} mode={mode} auth={auth} reason=bad_auth")
        sys.exit(1)

    exp_user=expected_user(auth)
    if user != exp_user:
        log(f"REJECT user={user} expected={exp_user} mode={mode} reason=bad_user")
        sys.exit(1)

    if mode == "free":
        hwid=parts[3].strip() if len(parts)>3 else ""
        proto=parts[4].strip() if len(parts)>4 else ""
        if not active_flag(cfg.get("FREE_ENABLED","1")):
            log(f"REJECT user={user} mode=free hwid={hwid} reason=free_off")
            sys.exit(1)
        if not hwid:
            log(f"REJECT user={user} mode=free reason=no_hwid")
            sys.exit(1)
        log(f"ACCEPT user={user} mode=free auth={auth} hwid={hwid} proto={proto}")
        sys.exit(0)

    if mode == "vip":
        if len(parts)<6:
            log(f"REJECT user={user} mode=vip reason=bad_vip_format")
            sys.exit(1)
        token=parts[3].strip(); hwid=parts[4].strip(); proto=parts[5].strip()
        ok,reason=vip_ok(token,hwid,cfg)
        if ok:
            log(f"ACCEPT user={user} mode=vip auth={auth} token={token} hwid={hwid} proto={proto} reason={reason}")
            sys.exit(0)
        log(f"REJECT user={user} mode=vip auth={auth} token={token} hwid={hwid} reason={reason}")
        sys.exit(1)

    log(f"REJECT user={user} mode={mode} reason=bad_mode")
    sys.exit(1)

if __name__ == "__main__":
    main()
PY
  chmod 700 "$PAM_SCRIPT"
}

write_token_manager(){
  msg "Instalando gestor correcto: netvpn-vip..."
  cat > "$TOKEN_MANAGER" <<'SH'
#!/usr/bin/env bash
set -e

CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"

ensure_files(){
  mkdir -p /etc
  touch "$VIP_DB"
  chmod 600 "$VIP_DB" || true
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<CFG
AUTH_LIST=localhost
FREE_ENABLED=1
VIP_DB=$VIP_DB
LOG=/var/log/netvpn-auth-login.log
CFG
  fi
}

get_auth(){ grep -E '^AUTH_LIST=' "$CONF" 2>/dev/null | cut -d= -f2- | head -1; }
get_free(){ grep -E '^FREE_ENABLED=' "$CONF" 2>/dev/null | cut -d= -f2- | head -1; }
set_conf_value(){
  key="$1"; val="$2"
  ensure_files
  if grep -q "^${key}=" "$CONF"; then sed -i "s#^${key}=.*#${key}=${val}#" "$CONF"; else echo "${key}=${val}" >> "$CONF"; fi
}
set_free(){ set_conf_value FREE_ENABLED "$1"; }

calc_exp(){
  v="$1"
  if echo "$v" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then echo "$v"; else date -d "+${v} days" +%F; fi
}

add_token(){
  token="$1"; days_or_date="${2:-30}"; cliente="${3:-Cliente VIP}"; hwid="${4:-}"
  [ -z "$token" ] && { echo 'Uso: netvpn-vip add TOKEN DIAS|YYYY-MM-DD "Cliente" [HWID]'; exit 1; }
  exp="$(calc_exp "$days_or_date")"
  grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  echo "${token}|${exp}|${hwid}|active|${cliente}" >> "$VIP_DB"
  chmod 600 "$VIP_DB"
  echo "OK token creado/renovado"
  echo "Token: $token"
  echo "Cliente: $cliente"
  echo "Vence: $exp"
  if [ -z "$hwid" ]; then echo "HWID: se vinculara al primer uso"; else echo "HWID: $hwid"; fi
}

list_tokens(){
  ensure_files
  echo "=== FREE ==="
  echo "FREE_ENABLED=$(get_free)"
  echo
  echo "=== VIP TOKENS ==="
  if [ ! -s "$VIP_DB" ]; then echo "Sin tokens"; return; fi
  awk -F'|' 'BEGIN{printf "%-4s %-22s %-12s %-18s %-10s %s\n","N","TOKEN","VENCE","HWID","ESTADO","CLIENTE"} {printf "%-4s %-22s %-12s %-18s %-10s %s\n",NR,$1,$2,($3==""?"(primer uso)":$3),$4,$5}' "$VIP_DB"
}

block_token(){ token="$1"; [ -z "$token" ] && { echo "Uso: netvpn-vip block TOKEN"; exit 1; }; awk -F'|' -v T="$token" 'BEGIN{OFS="|"} $1==T{$4="blocked"} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "OK bloqueado: $token"; }
active_token(){ token="$1"; [ -z "$token" ] && { echo "Uso: netvpn-vip active TOKEN"; exit 1; }; awk -F'|' -v T="$token" 'BEGIN{OFS="|"} $1==T{$4="active"} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "OK activo: $token"; }
del_token(){ token="$1"; [ -z "$token" ] && { echo "Uso: netvpn-vip del TOKEN"; exit 1; }; grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "OK eliminado: $token"; }
bind_token(){ token="$1"; hwid="$2"; [ -z "$token" ] || [ -z "$hwid" ] && { echo "Uso: netvpn-vip bind TOKEN HWID"; exit 1; }; awk -F'|' -v T="$token" -v H="$hwid" 'BEGIN{OFS="|"} $1==T{$3=H} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "OK vinculado: $token -> $hwid"; }
reset_bind(){ token="$1"; [ -z "$token" ] && { echo "Uso: netvpn-vip reset TOKEN"; exit 1; }; awk -F'|' -v T="$token" 'BEGIN{OFS="|"} $1==T{$3=""} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "OK reset HWID: $token"; }
status(){ ensure_files; echo "AUTH=$(get_auth)"; echo "FREE_ENABLED=$(get_free)"; echo "API:"; curl -s http://127.0.0.1:5000/health || true; echo; }

menu(){
  ensure_files
  while true; do
    clear || true
    echo "=========================================="
    echo "       NETVPN AUTH LOGIN - TOKEN MANAGER"
    echo "=========================================="
    echo "AUTH: $(get_auth)"
    echo "FREE: $(get_free)"
    echo
    echo "[1] Crear/Renovar token VIP"
    echo "[2] Listar tokens"
    echo "[3] Bloquear token"
    echo "[4] Activar token"
    echo "[5] Eliminar token"
    echo "[6] Apagar FREE"
    echo "[7] Encender FREE"
    echo "[8] Vincular token a HWID"
    echo "[9] Resetear HWID de token (primer uso)"
    echo "[10] Estado API"
    echo "[0] Salir"
    echo
    read -rp "Elige opcion: " op
    case "$op" in
      1) read -rp "Token: " t; read -rp "Dias o fecha YYYY-MM-DD: " d; read -rp "Cliente: " c; add_token "$t" "$d" "$c"; read -rp "ENTER..." ;;
      2) list_tokens; read -rp "ENTER..." ;;
      3) read -rp "Token: " t; block_token "$t"; read -rp "ENTER..." ;;
      4) read -rp "Token: " t; active_token "$t"; read -rp "ENTER..." ;;
      5) read -rp "Token: " t; del_token "$t"; read -rp "ENTER..." ;;
      6) set_free 0; echo "FREE apagado"; read -rp "ENTER..." ;;
      7) set_free 1; echo "FREE encendido"; read -rp "ENTER..." ;;
      8) read -rp "Token: " t; read -rp "HWID: " h; bind_token "$t" "$h"; read -rp "ENTER..." ;;
      9) read -rp "Token: " t; reset_bind "$t"; read -rp "ENTER..." ;;
      10) status; read -rp "ENTER..." ;;
      0) exit 0 ;;
      *) echo "Opcion invalida"; sleep 1 ;;
    esac
  done
}

ensure_files
cmd="${1:-menu}"; shift || true
case "$cmd" in
  add) add_token "$@" ;;
  list) list_tokens ;;
  block) block_token "$@" ;;
  active) active_token "$@" ;;
  del|delete|rm) del_token "$@" ;;
  bind) bind_token "$@" ;;
  reset|unbind) reset_bind "$@" ;;
  free-on) set_free 1; echo "FREE encendido" ;;
  free-off) set_free 0; echo "FREE apagado" ;;
  status) status ;;
  menu) menu ;;
  *) echo "Uso: netvpn-vip menu|add|list|block|active|del|bind|reset|free-on|free-off|status"; exit 1 ;;
esac
SH
  chmod +x "$TOKEN_MANAGER"

  cat >/usr/local/bin/svrtoken <<'SH'
#!/usr/bin/env bash
echo "SVRTOKEN viejo ya no se usa con NETVPN AUTH LOGIN."
echo "Abriendo gestor correcto: netvpn-vip"
sleep 1
exec /usr/local/bin/netvpn-vip menu
SH
  chmod +x /usr/local/bin/svrtoken
}

write_status_api(){
  msg "Instalando API limpia 5000 /checkUser..."
  cat > "$STATUS_API" <<'PY'
#!/usr/bin/env python3
import json, datetime, os
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

CONF="/etc/netvpn-auth-login.conf"

def read_conf():
    d={}
    try:
        for line in open(CONF):
            line=line.strip()
            if line and "=" in line and not line.startswith("#"):
                k,v=line.split("=",1); d[k.strip()]=v.strip()
    except Exception:
        pass
    return d

def yes(v): return str(v).lower().strip() in ("1","true","active","activo","on","yes","si")
def send(h, code, obj):
    b=json.dumps(obj,ensure_ascii=False).encode()
    h.send_response(code)
    h.send_header("Content-Type","application/json; charset=utf-8")
    h.send_header("Access-Control-Allow-Origin","*")
    h.send_header("Access-Control-Allow-Headers","Content-Type, Authorization")
    h.send_header("Access-Control-Allow-Methods","GET, POST, OPTIONS")
    h.send_header("Content-Length",str(len(b)))
    h.end_headers(); h.wfile.write(b)

def body(h):
    n=int(h.headers.get("Content-Length","0") or 0)
    raw=h.rfile.read(n).decode(errors="ignore") if n else ""
    if not raw: return {}
    try: return json.loads(raw)
    except Exception:
        q=parse_qs(raw); return {k:(v[0] if v else "") for k,v in q.items()}

def rewrite_db(db, rows):
    try:
        with open(db,"w",encoding="utf-8") as f:
            for r in rows: f.write("|".join(r)+"\n")
        os.chmod(db,0o600)
    except Exception: pass

def find_vip(token, hwid):
    cfg=read_conf(); db=cfg.get("VIP_DB","/etc/netvpn-vip.tokens"); today=datetime.date.today()
    rows=[]; found_i=None; found=None
    try: lines=open(db,encoding="utf-8",errors="ignore").read().splitlines()
    except Exception: lines=[]
    for line in lines:
        line=line.strip()
        if not line or line.startswith("#"): continue
        p=[x.strip() for x in line.split("|")]
        while len(p)<5: p.append("")
        if p[0]==token and found is None:
            found_i=len(rows); found=p[:5]
        rows.append(p[:5])
    if found is None:
        return {"ok":False,"active":False,"valid":False,"status":"not_found","estado":"no_activo","reason":"vip_not_found","message":"VIP no encontrado","cliente":"--","expires_text":"--","days_left":-1,"dias":-1}
    t, exp, saved_hwid, estado, cliente = found
    if not cliente: cliente="Cliente VIP"
    try: days=(datetime.date.fromisoformat(exp[:10])-today).days
    except Exception: days=-1
    bound_now=False
    if not saved_hwid and hwid:
        rows[found_i][2]=hwid; saved_hwid=hwid; bound_now=True; rewrite_db(db,rows)
    hwid_ok=(not saved_hwid) or saved_hwid=="*" or (hwid and saved_hwid==hwid)
    ok=yes(estado) and hwid_ok and days>=0
    reason="active" if ok else ("vip_expired" if days<0 else ("hwid_mismatch" if not hwid_ok else "inactive"))
    return {"ok":ok,"active":ok,"valid":ok,"status":"active" if ok else reason,"estado":"activo" if ok else reason,"reason":reason,"message":"ok" if ok else reason,"token":token,"token_id":token,"cliente":cliente,"client":cliente,"name":cliente,"username":cliente,"user":cliente,"expires_text":exp,"expires_at":exp,"fecha_vencimiento":exp,"vencimiento":exp,"days_left":days,"days":days,"dias":days,"dias_restantes":days,"hwid":hwid,"saved_hwid":saved_hwid,"bound_now":bound_now,"mode":"vip"}

def check(data):
    cfg=read_conf(); mode=str(data.get("mode") or data.get("tipo") or "").lower().strip(); token=str(data.get("token") or data.get("token_id") or data.get("vip_token") or data.get("key") or "").strip(); hwid=str(data.get("hwid") or data.get("device_id") or data.get("id") or data.get("android_id") or "").strip()
    if mode=="free":
        ok=yes(cfg.get("FREE_ENABLED","1"))
        return {"ok":ok,"active":ok,"valid":ok,"status":"active" if ok else "free_off","estado":"activo" if ok else "apagado","reason":"active" if ok else "free_off","message":"FREE activo" if ok else "FREE apagado","mode":"free"}
    if not token: return {"ok":False,"active":False,"valid":False,"status":"token_empty","estado":"no_activo","reason":"token_empty"}
    return find_vip(token,hwid)

class H(BaseHTTPRequestHandler):
    def log_message(self,*a): return
    def do_OPTIONS(self): send(self,200,{"ok":True})
    def do_GET(self):
        u=urlparse(self.path); q=parse_qs(u.query); data={k:(v[0] if v else "") for k,v in q.items()}; cfg=read_conf(); auth=cfg.get("AUTH_LIST","")
        if u.path in ("/","/health","/heartbeat"):
            send(self,200,{"ok":True,"service":"netvpn-auth-status-api","port":5000,"auth":auth,"free_enabled":cfg.get("FREE_ENABLED","1")}); return
        if u.path in ("/checkUser","/check-user","/api/checkUser","/vip/checkUser"):
            send(self,200,check(data)); return
        if u.path=="/online": send(self,200,{"ok":True,"online":0,"users":[]}); return
        if u.path in ("/config/free.json","/api/update/free","/config/vip.json","/api/update/vip","/meta","/update/meta"):
            send(self,200,{"ok":True,"status":"active","auth":auth,"version":0,"server_version":0,"no_update":True}); return
        send(self,404,{"ok":False,"reason":"not_found","path":u.path})
    def do_POST(self):
        u=urlparse(self.path); data=body(self)
        if u.path in ("/checkUser","/check-user","/api/checkUser","/vip/checkUser"):
            send(self,200,check(data)); return
        send(self,404,{"ok":False,"reason":"not_found","path":u.path})

ThreadingHTTPServer(("0.0.0.0",5000),H).serve_forever()
PY
  chmod +x "$STATUS_API"
  python3 -m py_compile "$STATUS_API"

  cat >/etc/systemd/system/netvpn-auth-status-api.service <<SERVICE
[Unit]
Description=NETVPN Auth Status API 5000
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $STATUS_API
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE
}

install_auth_login(){
  ask_auth_main
  clear || true
  echo "============================================================"
  echo " NETVPN AUTH LOGIN + TOKEN MANAGER + API VIP DATOS"
  echo "============================================================"
  echo "AUTH_MAIN=$AUTH_MAIN"
  echo "BACKUP_DIR=$BACKUP_DIR"
  echo

  mkdir -p "$BACKUP_DIR"
  if [ ! -f "$BRIDGE" ]; then
    err "ERROR: no existe $BRIDGE"
    echo "Primero instala protocolos base o revisa SVRCODE."
    exit 1
  fi

  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y python3 openssh-server sshpass curl >/dev/null 2>&1 || true

  cp -a "$BRIDGE" "$BACKUP_DIR/ssh_payload_bridge.py.bak" 2>/dev/null || true
  cp -a /etc/pam.d/sshd "$BACKUP_DIR/pam_sshd.bak" 2>/dev/null || true
  cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak" 2>/dev/null || true
  cp -a /etc/ssh/sshd_config.d "$BACKUP_DIR/sshd_config.d.bak" 2>/dev/null || true

  cat > /root/REVERT_NETVPN_AUTH_LOGIN.sh <<REV
#!/usr/bin/env bash
set -e
echo "=== REVERT NETVPN AUTH LOGIN ==="
cp -a "$BACKUP_DIR/ssh_payload_bridge.py.bak" "$BRIDGE" 2>/dev/null || true
cp -a "$BACKUP_DIR/pam_sshd.bak" /etc/pam.d/sshd 2>/dev/null || true
rm -f /etc/ssh/sshd_config.d/99-netvpn-auth-login-2290.conf
systemctl restart ssh || systemctl restart sshd || true
systemctl restart svrcode-ssh-payload.service || true
systemctl stop netvpn-auth-status-api.service 2>/dev/null || true
systemctl disable netvpn-auth-status-api.service 2>/dev/null || true
echo "Revertido lo principal."
REV
  chmod +x /root/REVERT_NETVPN_AUTH_LOGIN.sh

  msg "1) Configuracion AUTH..."
  mkdir -p /etc
  touch "$VIP_DB" "$LOG"
  chmod 600 "$VIP_DB" "$LOG" || true
  FREE_ENABLED="$(grep -E '^FREE_ENABLED=' "$CONF" 2>/dev/null | cut -d= -f2- | head -1 || true)"
  [ -z "$FREE_ENABLED" ] && FREE_ENABLED="1"
  cat > "$CONF" <<CFG
AUTH_LIST=$AUTH_MAIN
FREE_ENABLED=$FREE_ENABLED
VIP_DB=$VIP_DB
LOG=$LOG
CFG
  cat "$CONF"

  write_pam_validator
  write_token_manager

  msg "4) Configurando OpenSSH backend 2290..."
  mkdir -p /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-netvpn-auth-login-2290.conf <<'SSHD'
Port 2290
UsePAM yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
PubkeyAuthentication yes
AllowTcpForwarding yes
PermitTunnel yes
X11Forwarding no
SSHD

  msg "5) Configurando PAM sshd..."
  python3 - <<'PY'
from pathlib import Path
p=Path('/etc/pam.d/sshd')
s=p.read_text(errors='ignore')
start='# NETVPN_AUTH_LOGIN_START'; end='# NETVPN_AUTH_LOGIN_END'
while start in s and end in s:
    a=s.index(start); b=s.index(end)+len(end); s=s[:a]+s[b:]
lines=[ln for ln in s.splitlines() if 'netvpn-auth-login-pam.py' not in ln]
block=[start,'auth sufficient pam_exec.so quiet expose_authtok /usr/local/bin/netvpn-auth-login-pam.py',end]
p.write_text('\n'.join(block+lines)+'\n')
PY

  msg "6) Usuario tecnico nvp_<auth>..."
  NVP_USER="$(python3 - <<PY
import hashlib
auth='$AUTH_MAIN'
print('nvp_'+hashlib.sha256(auth.encode()).hexdigest()[:12])
PY
)"
  if ! id "$NVP_USER" >/dev/null 2>&1; then useradd -m -s /bin/bash "$NVP_USER"; fi
  RANDPASS="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"
  echo "$NVP_USER:$RANDPASS" | chpasswd
  chage -M 99999 "$NVP_USER" || true

  msg "7) Parcheando bridge 7789 -> 2290..."
  python3 - "$BRIDGE" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); s=p.read_text(errors='ignore')
s=re.sub(r'DROPBEAR\s*=\s*\(\s*["\']127\.0\.0\.1["\']\s*,\s*\d+\s*\)', 'DROPBEAR = ("127.0.0.1", 2290)', s)
s=s.replace('("127.0.0.1", 90)', '("127.0.0.1", 2290)')
s=s.replace("('127.0.0.1', 90)", "('127.0.0.1', 2290)")
p.write_text(s)
PY
  python3 -m py_compile "$BRIDGE"

  msg "8) API limpia 5000: reemplaza token viejo si existe..."
  stop_old_apis_free_5000
  write_status_api

  msg "9) Reiniciando servicios..."
  systemctl daemon-reload
  systemctl enable netvpn-auth-status-api.service >/dev/null
  sshd -t
  systemctl restart ssh || systemctl restart sshd
  systemctl restart netvpn-auth-status-api.service
  systemctl enable svrcode-ssh-payload.service >/dev/null 2>&1 || true
  systemctl restart svrcode-ssh-payload.service
  ufw allow 2290/tcp >/dev/null 2>&1 || true
  ufw allow 5000/tcp >/dev/null 2>&1 || true

  msg "10) Pruebas..."
  TEST_PASS="NVP1|free|$AUTH_MAIN|TESTHWID|ssh"
  OUT="$(timeout 12 sshpass -p "$TEST_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -p 2290 "$NVP_USER@127.0.0.1" 'echo OK_AUTH_LOGIN' 2>&1 || true)"
  echo "$OUT"
  echo "--- API health ---"; curl -s http://127.0.0.1:5000/health; echo
  echo "--- FREE check ---"; curl -s 'http://127.0.0.1:5000/checkUser?mode=free'; echo
  echo "--- Bridge ---"; grep -nE 'LISTEN_PORT|DROPBEAR|2290' "$BRIDGE" | head -20 || true
  echo "--- Puertos ---"; ss -ltnp | grep -E ':80|:7789|:2290|:5000' || true

  echo
  msg "=== LISTO ==="
  echo "AUTH_MAIN=$AUTH_MAIN"
  echo "NVP_USER=$NVP_USER"
  echo "Gestor correcto: netvpn-vip menu"
  echo "FREE: netvpn-vip free-off | netvpn-vip free-on"
  echo "Crear VIP: netvpn-vip add TOKEN 15 \"Cliente\""
  echo "Revertir: bash /root/REVERT_NETVPN_AUTH_LOGIN.sh"
}

show_menu(){
  clear || true
  echo "============================================================"
  echo "   NETVPN AUTH LOGIN - INSTALADOR UNICO V4"
  echo "============================================================"
  echo "AUTH detectado: $(detected_auth || true)"
  echo
  echo "[1] Instalar protocolos base + NETVPN AUTH LOGIN"
  echo "[2] Solo instalar NETVPN AUTH LOGIN / TOKEN MANAGER"
  echo "[3] Solo instalar protocolos base"
  echo "[0] Salir"
  echo
  read -rp "Selecciona una opcion: " op
  case "$op" in
    1) install_protocolos_base; install_auth_login ;;
    2) install_auth_login ;;
    3) install_protocolos_base ;;
    0) exit 0 ;;
    *) echo "Opcion invalida"; exit 1 ;;
  esac
}

main(){
  require_root
  case "$INSTALL_MODE" in
    full) install_protocolos_base; install_auth_login ;;
    auth) install_auth_login ;;
    protocolos) install_protocolos_base ;;
    menu) show_menu ;;
    *) err "INSTALL_MODE invalido: $INSTALL_MODE"; exit 1 ;;
  esac
}

main "$@"
