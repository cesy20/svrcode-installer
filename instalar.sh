#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"
TOKEN_MANAGER="/usr/local/bin/netvpn-vip"
STATUS_API="/usr/local/bin/netvpn-auth-status-api.py"
PAM_SCRIPT="/usr/local/bin/netvpn-auth-login-pam.py"
SECRET_FILE="/etc/netvpn-auth-login.secret"

mkdir -p /etc /usr/local/bin
[ -f "$TOKEN_MANAGER" ] && cp -a "$TOKEN_MANAGER" "$TOKEN_MANAGER.bak_v7c_$(date +%F_%H%M%S)" || true
[ -f "$STATUS_API" ] && cp -a "$STATUS_API" "$STATUS_API.bak_v7c_$(date +%F_%H%M%S)" || true
[ -f "$PAM_SCRIPT" ] && cp -a "$PAM_SCRIPT" "$PAM_SCRIPT.bak_v7c_$(date +%F_%H%M%S)" || true

touch "$VIP_DB" "$LOG"
chmod 600 "$VIP_DB" "$LOG" 2>/dev/null || true
perl -pi -e 's/\x00//g' "$VIP_DB" 2>/dev/null || true

if [ ! -s "$SECRET_FILE" ]; then
  python3 - <<'PY_SECRET' > "$SECRET_FILE"
import secrets
print(secrets.token_urlsafe(48))
PY_SECRET
  chmod 600 "$SECRET_FILE" 2>/dev/null || true
fi

if [ ! -f "$CONF" ]; then
cat > "$CONF" <<CFG
AUTH_LIST=localhost
FREE_ENABLED=1
VIP_DB=$VIP_DB
LOG=$LOG
CFG
fi

# Normaliza DB vieja: TOKEN|FECHA|HWID|active|Cliente -> TOKEN|FECHA|HWID|active|Cliente|all
python3 - <<'PY_NORM'
from pathlib import Path
p=Path('/etc/netvpn-vip.tokens')
rows=[]
if p.exists():
    for line in p.read_text(errors='ignore').splitlines():
        line=line.replace('\x00','').strip()
        if not line or line.startswith('#'):
            continue
        parts=[x.strip() for x in line.split('|')]
        while len(parts)<6:
            parts.append('')
        if not parts[5]:
            parts[5]='all'
        if parts[5].lower() not in ('all','ssh','xray','singbox'):
            parts[5]='all'
        rows.append('|'.join(parts[:6]))
p.write_text('\n'.join(rows)+('\n' if rows else ''), encoding='utf-8')
p.chmod(0o600)
PY_NORM

cat > "$PAM_SCRIPT" <<'PY_PAM'
#!/usr/bin/env python3
import sys, os, hashlib, datetime

CONF="/etc/netvpn-auth-login.conf"

def read_conf():
    d={}
    try:
        for line in open(CONF, encoding="utf-8", errors="ignore"):
            line=line.strip()
            if line and "=" in line and not line.startswith("#"):
                k,v=line.split("=",1)
                d[k.strip()]=v.strip()
    except Exception:
        pass
    return d

def log(msg):
    cfg=read_conf(); path=cfg.get("LOG","/var/log/netvpn-auth-login.log")
    try:
        with open(path,"a",encoding="utf-8") as f:
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

def normalize_proto(p):
    p=str(p or "").strip().lower()
    return p if p in ("ssh","xray","singbox") else "ssh"

def allowed_proto(p):
    p=str(p or "all").strip().lower()
    return p if p in ("all","ssh","xray","singbox") else "all"

def proto_ok(allowed, requested):
    allowed=allowed_proto(allowed)
    requested=normalize_proto(requested)
    return allowed=="all" or allowed==requested

def rewrite_vip_db(db, rows):
    try:
        with open(db,"w",encoding="utf-8") as f:
            for r in rows:
                while len(r)<6: r.append("")
                if not r[5]: r[5]="all"
                f.write("|".join(r[:6])+"\n")
        os.chmod(db,0o600)
    except Exception:
        pass

def vip_ok(token, hwid, cfg, proto="ssh"):
    db=cfg.get("VIP_DB","/etc/netvpn-vip.tokens")
    today=datetime.date.today()
    rows=[]; found_index=None; found=None
    try:
        with open(db, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line=line.replace("\x00","").strip()
                if not line or line.startswith("#"):
                    continue
                p=[x.strip() for x in line.split("|")]
                while len(p)<6: p.append("")
                if not p[5]: p[5]="all"
                if p[0] == token and found is None:
                    found_index=len(rows); found=p[:6]
                rows.append(p[:6])
    except Exception:
        return False, "vip_db_error"

    if found is None:
        return False, "vip_not_found"

    t, exp, saved_hwid, st, name, proto_allowed = found[:6]
    if not active_flag(st):
        return False, "vip_inactive"
    try:
        if datetime.date.fromisoformat(exp[:10]) < today:
            return False, "vip_expired"
    except Exception:
        return False, "vip_bad_expire"

    if not proto_ok(proto_allowed, proto):
        return False, "proto_not_allowed"

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
        proto=normalize_proto(parts[4].strip() if len(parts)>4 else "ssh")
        if not active_flag(cfg.get("FREE_ENABLED","1")):
            log(f"REJECT user={user} mode=free hwid={hwid} proto={proto} reason=free_off")
            sys.exit(1)
        if not hwid:
            log(f"REJECT user={user} mode=free proto={proto} reason=no_hwid")
            sys.exit(1)
        log(f"ACCEPT user={user} mode=free auth={auth} hwid={hwid} proto={proto}")
        sys.exit(0)

    if mode == "vip":
        if len(parts)<6:
            log(f"REJECT user={user} mode=vip reason=bad_vip_format")
            sys.exit(1)
        token=parts[3].strip(); hwid=parts[4].strip(); proto=normalize_proto(parts[5].strip())
        ok,reason=vip_ok(token,hwid,cfg,proto)
        if ok:
            log(f"ACCEPT user={user} mode=vip auth={auth} token={token} hwid={hwid} proto={proto} reason={reason}")
            sys.exit(0)
        log(f"REJECT user={user} mode=vip auth={auth} token={token} hwid={hwid} proto={proto} reason={reason}")
        sys.exit(1)

    log(f"REJECT user={user} mode={mode} reason=bad_mode")
    sys.exit(1)

if __name__ == "__main__":
    main()
PY_PAM
chmod 700 "$PAM_SCRIPT"
python3 -m py_compile "$PAM_SCRIPT"

cat > "$STATUS_API" <<'PY_API'
#!/usr/bin/env python3
import json, datetime, os, uuid, hashlib, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

CONF="/etc/netvpn-auth-login.conf"
SECRET_FILE="/etc/netvpn-auth-login.secret"

def read_conf():
    d={}
    try:
        for line in open(CONF, encoding="utf-8", errors="ignore"):
            line=line.strip()
            if line and "=" in line and not line.startswith("#"):
                k,v=line.split("=",1); d[k.strip()]=v.strip()
    except Exception:
        pass
    return d

def read_secret():
    try:
        s=open(SECRET_FILE, encoding="utf-8", errors="ignore").read().strip()
        if s: return s
    except Exception:
        pass
    return "netvpn-default-secret"

def yes(v): return str(v).lower().strip() in ("1","true","active","activo","on","yes","si")
def normalize_proto(p):
    p=str(p or "").strip().lower()
    if p in ("xray","v2ray","vmess","vless"): return "xray"
    if p in ("sing","sing-box","singbox"): return "singbox"
    if p == "ssh": return "ssh"
    return "xray"

def allowed_proto(p):
    p=str(p or "all").strip().lower()
    return p if p in ("all","ssh","xray","singbox") else "all"

def proto_ok(allowed, requested):
    requested=normalize_proto(requested)
    allowed=allowed_proto(allowed)
    return allowed=="all" or allowed==requested

def first_auth(cfg):
    a=cfg.get("AUTH_LIST","").replace(","," ").split()
    return a[0] if a else ""

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
            for r in rows:
                while len(r)<6: r.append("")
                if not r[5]: r[5]="all"
                f.write("|".join(r[:6])+"\n")
        os.chmod(db,0o600)
    except Exception: pass

def find_vip(token, hwid):
    cfg=read_conf(); db=cfg.get("VIP_DB","/etc/netvpn-vip.tokens"); today=datetime.date.today()
    rows=[]; found_i=None; found=None
    try: lines=open(db,encoding="utf-8",errors="ignore").read().splitlines()
    except Exception: lines=[]
    for line in lines:
        line=line.replace("\x00","").strip()
        if not line or line.startswith("#"): continue
        p=[x.strip() for x in line.split("|")]
        while len(p)<6: p.append("")
        if not p[5]: p[5]="all"
        if p[0]==token and found is None:
            found_i=len(rows); found=p[:6]
        rows.append(p[:6])
    if found is None:
        return {"ok":False,"active":False,"valid":False,"status":"not_found","estado":"no_activo","reason":"vip_not_found","message":"VIP no encontrado","cliente":"--","expires_text":"--","days_left":-1,"dias":-1,"allowed_proto":"all","proto":"all"}
    t, exp, saved_hwid, estado, cliente, proto_allowed = found[:6]
    if not cliente: cliente="Cliente VIP"
    proto_allowed=allowed_proto(proto_allowed)
    try: days=(datetime.date.fromisoformat(exp[:10])-today).days
    except Exception: days=-1
    bound_now=False
    if not saved_hwid and hwid:
        rows[found_i][2]=hwid; saved_hwid=hwid; bound_now=True; rewrite_db(db,rows)
    hwid_ok=(not saved_hwid) or saved_hwid=="*" or (hwid and saved_hwid==hwid)
    ok=yes(estado) and hwid_ok and days>=0
    reason="active" if ok else ("vip_expired" if days<0 else ("hwid_mismatch" if not hwid_ok else "inactive"))
    return {"ok":ok,"active":ok,"valid":ok,"status":"active" if ok else reason,"estado":"activo" if ok else reason,"reason":reason,"message":"ok" if ok else reason,"token":token,"token_id":token,"cliente":cliente,"client":cliente,"name":cliente,"username":cliente,"user":cliente,"expires_text":exp,"expires_at":exp,"fecha_vencimiento":exp,"vencimiento":exp,"days_left":days,"days":days,"dias":days,"dias_restantes":days,"hwid":hwid,"saved_hwid":saved_hwid,"bound_now":bound_now,"mode":"vip","allowed_proto":proto_allowed,"proto":proto_allowed}

def check(data):
    cfg=read_conf()
    mode=str(data.get("mode") or data.get("tipo") or "").lower().strip()
    proto=normalize_proto(data.get("proto") or data.get("protocol") or data.get("type") or "")
    token=str(data.get("token") or data.get("token_id") or data.get("vip_token") or data.get("key") or "").strip()
    hwid=str(data.get("hwid") or data.get("device_id") or data.get("id") or data.get("android_id") or "").strip()
    if mode=="free":
        ok=yes(cfg.get("FREE_ENABLED","1"))
        return {"ok":ok,"active":ok,"valid":ok,"status":"active" if ok else "free_off","estado":"activo" if ok else "apagado","reason":"active" if ok else "free_off","message":"FREE activo" if ok else "FREE apagado","mode":"free","allowed_proto":"all","proto":proto}
    if not token: return {"ok":False,"active":False,"valid":False,"status":"token_empty","estado":"no_activo","reason":"token_empty","allowed_proto":"all","proto":proto}
    return find_vip(token,hwid)

def make_credential(data):
    cfg=read_conf()
    mode=str(data.get("mode") or data.get("tipo") or "").lower().strip()
    proto=normalize_proto(data.get("proto") or data.get("protocol") or data.get("type") or "xray")
    token=str(data.get("token") or data.get("token_id") or data.get("vip_token") or data.get("key") or "").strip()
    hwid=str(data.get("hwid") or data.get("device_id") or data.get("id") or data.get("android_id") or "").strip()
    auth=str(data.get("auth") or data.get("host") or first_auth(cfg)).strip()

    if proto not in ("xray","singbox"):
        return {"ok":False,"reason":"proto_not_dynamic","message":"SSH usa AUTH LOGIN directo; credential temporal solo para xray/singbox."}
    if not hwid:
        return {"ok":False,"reason":"no_hwid","message":"HWID requerido"}

    allowed="all"
    cliente="FREE"
    days=-1
    if mode=="free":
        if not yes(cfg.get("FREE_ENABLED","1")):
            return {"ok":False,"active":False,"reason":"free_off","message":"FREE apagado","mode":"free","proto":proto}
    elif mode=="vip":
        if not token:
            return {"ok":False,"active":False,"reason":"token_empty","message":"Token requerido","mode":"vip","proto":proto}
        info=find_vip(token,hwid)
        if not info.get("ok"):
            info["proto"]=proto
            return info
        allowed=allowed_proto(info.get("allowed_proto","all"))
        cliente=info.get("cliente","Cliente VIP")
        days=info.get("days_left",-1)
        if not proto_ok(allowed, proto):
            return {"ok":False,"active":False,"reason":"proto_not_allowed","message":"Protocolo no permitido para este token","mode":"vip","proto":proto,"allowed_proto":allowed,"cliente":cliente,"days_left":days}
    else:
        return {"ok":False,"reason":"bad_mode","message":"mode debe ser free o vip","proto":proto}

    now=int(time.time())
    bucket=now//300
    seed="|".join([read_secret(), auth, mode, token if mode=="vip" else "free", hwid, proto, str(bucket)])
    u=str(uuid.uuid5(uuid.NAMESPACE_URL, seed))
    password=hashlib.sha256((seed+"|pass").encode()).hexdigest()[:32]
    return {
        "ok": True,
        "active": True,
        "valid": True,
        "mode": mode,
        "proto": proto,
        "allowed_proto": allowed,
        "cliente": cliente,
        "days_left": days,
        "auth": auth,
        "host": auth,
        "uuid": u,
        "id": u,
        "password": password,
        "user": u,
        "expires_in": 300,
        "expires_at": now + (300 - (now % 300)),
        "dynamic": True,
        "template_only": True
    }

class H(BaseHTTPRequestHandler):
    def log_message(self,*a): return
    def do_OPTIONS(self): send(self,200,{"ok":True})
    def do_GET(self):
        u=urlparse(self.path); q=parse_qs(u.query); data={k:(v[0] if v else "") for k,v in q.items()}; cfg=read_conf(); auth=cfg.get("AUTH_LIST","")
        if u.path in ("/","/health","/heartbeat"):
            send(self,200,{"ok":True,"service":"netvpn-auth-status-api","version":"V7C_PROTO_DYNAMIC","port":5000,"auth":auth,"free_enabled":cfg.get("FREE_ENABLED","1")}); return
        if u.path in ("/checkUser","/check-user","/api/checkUser","/vip/checkUser"):
            send(self,200,check(data)); return
        if u.path in ("/proto/credential","/api/proto/credential","/credential","/dynamic/credential"):
            send(self,200,make_credential(data)); return
        if u.path=="/online": send(self,200,{"ok":True,"online":0,"users":[]}); return
        if u.path in ("/config/free.json","/api/update/free","/config/vip.json","/api/update/vip","/meta","/update/meta"):
            send(self,200,{"ok":True,"status":"active","auth":auth,"version":0,"server_version":0,"no_update":True}); return
        send(self,404,{"ok":False,"reason":"not_found","path":u.path})
    def do_POST(self):
        u=urlparse(self.path); data=body(self)
        if u.path in ("/checkUser","/check-user","/api/checkUser","/vip/checkUser"):
            send(self,200,check(data)); return
        if u.path in ("/proto/credential","/api/proto/credential","/credential","/dynamic/credential"):
            send(self,200,make_credential(data)); return
        send(self,404,{"ok":False,"reason":"not_found","path":u.path})

ThreadingHTTPServer(("0.0.0.0",5000),H).serve_forever()
PY_API
chmod +x "$STATUS_API"
python3 -m py_compile "$STATUS_API"

cat > "$TOKEN_MANAGER" <<'MANAGER_SH'
#!/usr/bin/env bash
set -e

CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"

C0='\033[0m'; B='\033[1m'; R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'; M='\033[1;35m'; W='\033[1;37m'

ensure_files(){
  mkdir -p /etc
  touch "$VIP_DB" "$LOG"
  chmod 600 "$VIP_DB" "$LOG" 2>/dev/null || true
  perl -pi -e 's/\x00//g' "$VIP_DB" 2>/dev/null || true
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<CFG
AUTH_LIST=localhost
FREE_ENABLED=1
VIP_DB=$VIP_DB
LOG=$LOG
CFG
  fi
}

norm_proto(){
  case "$(echo "${1:-all}" | tr 'A-Z' 'a-z' | tr -d ' ')" in
    ssh) echo ssh ;;
    xray|v2ray|vmess|vless) echo xray ;;
    sing|sing-box|singbox) echo singbox ;;
    all|*) echo all ;;
  esac
}

get_conf(){ grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2-; }
get_auth(){ get_conf AUTH_LIST; }
get_free(){ v="$(get_conf FREE_ENABLED)"; [ -z "$v" ] && v=1; echo "$v"; }
set_free(){ ensure_files; if grep -q '^FREE_ENABLED=' "$CONF"; then sed -i "s/^FREE_ENABLED=.*/FREE_ENABLED=$1/" "$CONF"; else echo "FREE_ENABLED=$1" >> "$CONF"; fi; }
is_active(){ echo "$1" | grep -Eiq '^(1|true|active|activo|on|yes|si)$'; }
today_epoch(){ date +%s; }
date_epoch(){ date -d "$1" +%s 2>/dev/null || echo 0; }
days_left(){ local e; e="$(date_epoch "$1")"; if [ "$e" = "0" ]; then echo -1; else echo $(( (e-$(today_epoch))/86400 )); fi; }
safe_lines(){ tr -d '\000' < "$VIP_DB" 2>/dev/null | grep -v '^[[:space:]]*$' | grep -v '^#' || true; }
count_total(){ safe_lines | wc -l | tr -d ' '; }
count_active(){ safe_lines | awk -F'|' 'tolower($4) ~ /^(active|activo|1|on|true)$/ {print}' | wc -l | tr -d ' '; }
count_block(){ safe_lines | awk -F'|' 'tolower($4) ~ /(block|bloq|off|0|false|inactive)/ {print}' | wc -l | tr -d ' '; }
count_nohwid(){ safe_lines | awk -F'|' '($3=="" || $3=="*") {print}' | wc -l | tr -d ' '; }
count_expired(){ safe_lines | while IFS='|' read -r token exp hwid st name proto rest; do d="$(days_left "$exp")"; [ "$d" -lt 0 ] && echo x; done | wc -l | tr -d ' '; }
online_count(){ ss -tn state established '( sport = :2290 or sport = :90 or sport = :80 )' 2>/dev/null | tail -n +2 | wc -l | tr -d ' '; }
pause(){ echo; read -rp "ENTER para continuar..." _; }

normalize_db(){
  tmp=/tmp/netvpn-vip.tokens.$$; : > "$tmp"
  while IFS='|' read -r token exp hwid st name proto rest; do
    [ -z "$token" ] && continue
    [ -z "$exp" ] && exp="$(date -d '+30 days' +%F)"
    [ -z "$st" ] && st="active"
    [ -z "$name" ] && name="Cliente VIP"
    proto="$(norm_proto "${proto:-all}")"
    echo "$token|$exp|$hwid|$st|$name|$proto" >> "$tmp"
  done < <(safe_lines)
  mv "$tmp" "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
}

print_header(){
  clear
  echo -e "${G}============================================================${C0}"
  echo -e "      🔐 ${W}NETVPN AUTH LOGIN - MANAGER V7C PROTO${C0}"
  echo -e "${G}============================================================${C0}"
  echo -e "🌐 AUTH : ${C}$(get_auth)${C0}"
  if [ "$(get_free)" = "1" ]; then f="${G}ON${C0}"; else f="${R}OFF${C0}"; fi
  echo -e "🟢 FREE : $f     👥 Online: ${C}$(online_count)${C0}"
  echo -e "🎫 Tokens: ${Y}$(count_total)${C0}   ✅ Activos: ${G}$(count_active)${C0}   ⛔ Bloq: ${R}$(count_block)${C0}   ⌛ Vencidos: ${R}$(count_expired)${C0}   📱 Sin HWID: ${Y}$(count_nohwid)${C0}"
  echo -e "${G}============================================================${C0}"
}

status_color(){
  local st="$1" exp="$2" d
  d="$(days_left "$exp")"
  if [ "$d" -lt 0 ]; then echo -e "${R}VENCIDO${C0}"; return; fi
  if is_active "$st"; then echo -e "${G}ACTIVO${C0}"; else echo -e "${R}BLOQUEADO${C0}"; fi
}

print_tokens(){
  ensure_files; normalize_db
  echo -e "${G}------------------------------------------------------------------------------------------------${C0}"
  printf "%b\n" "${W} #   TOKEN              CLIENTE             VENCE       DIAS   ESTADO       PROTO     HWID${C0}"
  echo -e "${G}------------------------------------------------------------------------------------------------${C0}"
  local i=0 any=0 d estado hwid_show dshow
  while IFS='|' read -r token exp hwid st name proto rest; do
    [ -z "$token" ] && continue
    any=1; i=$((i+1))
    [ -z "$name" ] && name="Cliente VIP"
    [ -z "$hwid" ] && hwid="SIN-HWID"
    proto="$(norm_proto "${proto:-all}")"
    d="$(days_left "$exp")"
    estado="$(status_color "$st" "$exp")"
    if [ "$hwid" = "*" ] || [ "$hwid" = "SIN-HWID" ]; then hwid_show="${Y}${hwid}${C0}"; else hwid_show="${C}${hwid:0:12}...${C0}"; fi
    if [ "$d" -lt 0 ]; then dshow="${R}${d}${C0}"; else dshow="${G}${d}${C0}"; fi
    printf "%b" "${Y}[$i]${C0} "
    printf "%-18s %-19s %-10s " "$token" "${name:0:19}" "$exp"
    printf "%b " "$dshow"
    printf "%b " "$estado"
    printf "%-8s " "$proto"
    printf "%b\n" "$hwid_show"
  done < <(safe_lines)
  [ "$any" = "0" ] && echo -e "${Y}Sin tokens VIP todavía.${C0}"
  echo -e "${G}------------------------------------------------------------------------------------------------${C0}"
}

token_by_num(){ local n="$1" i=0 token; while IFS='|' read -r token exp hwid st name proto rest; do [ -z "$token" ] && continue; i=$((i+1)); if [ "$i" = "$n" ]; then echo "$token"; return 0; fi; done < <(safe_lines); return 1; }
choose_token(){ print_tokens > /dev/tty; echo > /dev/tty; printf "Elige número: " > /dev/tty; read -r n < /dev/tty; token_by_num "$n"; }
rewrite_token_field(){ local token="$1" field="$2" value="$3"; normalize_db; awk -F'|' -v T="$token" -v F="$field" -v V="$value" 'BEGIN{OFS="|"} $1==T{$F=V} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens; mv /tmp/netvpn-vip.tokens "$VIP_DB"; chmod 600 "$VIP_DB" 2>/dev/null || true; }

ask_proto(){
  echo "Protocolos permitidos:"
  echo "1) all     (SSH + Xray + Sing-box)"
  echo "2) ssh"
  echo "3) xray"
  echo "4) singbox"
  read -rp "Elige protocolo [ENTER=all]: " p
  case "$p" in
    2|ssh|SSH) echo ssh ;;
    3|xray|XRAY|v2ray|vmess|vless) echo xray ;;
    4|sing|singbox|sing-box) echo singbox ;;
    *) echo all ;;
  esac
}

add_token(){
  ensure_files; normalize_db
  echo -e "${C}Crear / renovar VIP${C0}"
  read -rp "Token: " token
  read -rp "Días: " days
  read -rp "Cliente: " name
  proto="$(ask_proto)"
  [ -z "$days" ] && days=30
  [ -z "$name" ] && name="Cliente VIP"
  [ -z "$token" ] && { echo -e "${R}Token vacío.${C0}"; pause; return; }
  exp="$(date -d "+${days} days" +%F)"
  grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  echo "${token}|${exp}||active|${name}|${proto}" >> "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
  echo -e "${G}OK creado: $token vence $exp. PROTO=$proto. HWID: primer uso.${C0}"
  pause
}

block_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { rewrite_token_field "$token" 4 "blocked"; echo -e "${G}OK bloqueado.${C0}"; }; pause; }
active_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { rewrite_token_field "$token" 4 "active"; echo -e "${G}OK activo.${C0}"; }; pause; }
del_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo -e "${G}OK eliminado.${C0}"; }; pause; }
renew_token(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "Días nuevos: " d; [ -z "$d" ] && d=30; exp="$(date -d "+${d} days" +%F)"; rewrite_token_field "$token" 2 "$exp"; rewrite_token_field "$token" 4 "active"; echo -e "${G}OK renovado hasta $exp.${C0}"; pause; }
rename_token(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "Nuevo cliente: " name; [ -z "$name" ] && name="Cliente VIP"; rewrite_token_field "$token" 5 "$name"; echo -e "${G}OK nombre cambiado.${C0}"; pause; }
change_proto(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; proto="$(ask_proto)"; rewrite_token_field "$token" 6 "$proto"; echo -e "${G}OK protocolo cambiado a $proto.${C0}"; pause; }
bind_hwid(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "HWID: " hw; rewrite_token_field "$token" 3 "$hw"; echo -e "${G}OK HWID vinculado.${C0}"; pause; }
reset_hwid(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; rewrite_token_field "$token" 3 ""; echo -e "${G}OK HWID reseteado. Se vinculará al primer uso.${C0}"; pause; }

status_api(){
  echo -e "${C}API 5000:${C0}"; curl -s http://127.0.0.1:5000/health || true; echo
  echo -e "${C}FREE:${C0}"; curl -s 'http://127.0.0.1:5000/checkUser?mode=free&proto=xray' || true; echo
  echo -e "${C}Credential FREE XRAY:${C0}"; curl -s 'http://127.0.0.1:5000/proto/credential?mode=free&hwid=TESTHWID&proto=xray' || true; echo
  echo -e "${C}Servicios:${C0}"; systemctl is-active netvpn-auth-status-api.service 2>/dev/null || true; systemctl is-active svrcode-ssh-payload.service 2>/dev/null || true
  pause
}
show_logs(){ tail -100 "$LOG" 2>/dev/null || echo "Sin log"; pause; }
open_gen(){ if command -v gen >/dev/null 2>&1; then gen; return; fi; if command -v svrcode >/dev/null 2>&1; then svrcode; return; fi; if [ -x /opt/svrcode/menu.sh ]; then bash /opt/svrcode/menu.sh; return; fi; echo -e "${Y}No encontré menú original GEN / métodos.${C0}"; pause; }

menu(){
  ensure_files; normalize_db
  while true; do
    print_header
    echo -e "${Y}[1]${C0}  ➕ Crear / Renovar token VIP"
    echo -e "${Y}[2]${C0}  📋 Listar tokens"
    echo -e "${Y}[3]${C0}  ⛔ Bloquear"
    echo -e "${Y}[4]${C0}  ✅ Activar"
    echo -e "${Y}[5]${C0}  🗑️  Eliminar"
    echo -e "${Y}[6]${C0}  📅 Renovar días"
    echo -e "${Y}[7]${C0}  ✏️  Cambiar nombre"
    echo -e "${Y}[8]${C0}  🔀 Cambiar protocolo"
    echo -e "${Y}[9]${C0}  📱 Vincular HWID"
    echo -e "${Y}[10]${C0} ♻️  Resetear HWID"
    echo -e "${Y}[11]${C0} 🔴 Apagar FREE"
    echo -e "${Y}[12]${C0} 🟢 Encender FREE"
    echo -e "${Y}[13]${C0} 🛠️  Estado API"
    echo -e "${Y}[14]${C0} ⚙️  GEN / Métodos"
    echo -e "${Y}[15]${C0} 📜 Logs AUTH"
    echo -e "${Y}[0]${C0}  🚪 Salir"
    echo -e "${G}------------------------------------------------------------${C0}"
    read -rp "Elige opción: " op
    case "$op" in
      1) add_token ;; 2) print_tokens; pause ;; 3) block_token ;; 4) active_token ;; 5) del_token ;; 6) renew_token ;; 7) rename_token ;; 8) change_proto ;; 9) bind_hwid ;; 10) reset_hwid ;; 11) set_free 0; echo -e "${G}FREE apagado.${C0}"; pause ;; 12) set_free 1; echo -e "${G}FREE encendido.${C0}"; pause ;; 13) status_api ;; 14) open_gen ;; 15) show_logs ;; 0) exit 0 ;; *) echo -e "${R}Opción inválida.${C0}"; sleep 1 ;;
    esac
  done
}

ensure_files; normalize_db
cmd="${1:-menu}"; shift || true
case "$cmd" in
  menu) menu ;;
  list) print_tokens ;;
  add)
    token="${1:-}"; days="${2:-30}"; name="${3:-Cliente VIP}"; hwid="${4:-}"; proto="$(norm_proto "${5:-all}")"
    [ -z "$token" ] && { echo 'Uso: netvpn-vip add TOKEN DIAS "Cliente" [HWID] [all|ssh|xray|singbox]'; exit 1; }
    exp="$(date -d "+${days} days" +%F)"; grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "${token}|${exp}|${hwid}|active|${name}|${proto}" >> "$VIP_DB"; echo "OK $token $exp proto=$proto" ;;
  proto) token="${1:-}"; proto="$(norm_proto "${2:-all}")"; [ -z "$token" ] && { echo 'Uso: netvpn-vip proto TOKEN all|ssh|xray|singbox'; exit 1; }; rewrite_token_field "$token" 6 "$proto"; echo "OK proto=$proto" ;;
  free-on) set_free 1; echo "FREE ON" ;;
  free-off) set_free 0; echo "FREE OFF" ;;
  status) status_api ;;
  gen) open_gen ;;
  *) echo "Uso: netvpn-vip menu|list|add|proto|free-on|free-off|status|gen" ;;
esac
MANAGER_SH
chmod +x "$TOKEN_MANAGER"

cat >/usr/local/bin/svrtoken <<'SVRTOKEN_SH'
#!/usr/bin/env bash
exec /usr/local/bin/netvpn-vip menu
SVRTOKEN_SH
chmod +x /usr/local/bin/svrtoken

if systemctl list-unit-files | grep -q '^netvpn-auth-status-api.service'; then
  systemctl daemon-reload
  systemctl restart netvpn-auth-status-api.service || true
fi
if command -v sshd >/dev/null 2>&1; then
  sshd -t && (systemctl restart ssh || systemctl restart sshd || true)
fi

echo "OK: NETVPN V7C PROTO instalado."
echo "- Token proto por defecto: all"
echo "- Manager: netvpn-vip"
echo "- API: /checkUser y /proto/credential"
echo "- No se tocaron configuraciones base de Xray/Sing-box."
