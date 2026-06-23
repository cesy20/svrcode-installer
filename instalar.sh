#!/usr/bin/env bash
set -euo pipefail

STATUS_API="/usr/local/bin/netvpn-auth-status-api.py"
CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
SECRET_FILE="/etc/netvpn-auth-login.secret"
XRAY_CFG="/usr/local/etc/xray/config.json"
SERVICE="/etc/systemd/system/netvpn-auth-status-api.service"

mkdir -p /usr/local/bin /etc /var/log
[ -f "$STATUS_API" ] && cp -a "$STATUS_API" "$STATUS_API.bak_v7e_$(date +%F_%H%M%S)" || true
[ -f "$XRAY_CFG" ] && cp -a "$XRAY_CFG" "$XRAY_CFG.bak_v7e_$(date +%F_%H%M%S)" || true
[ -f "$VIP_DB" ] || touch "$VIP_DB"
chmod 600 "$VIP_DB" 2>/dev/null || true

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
LOG=/var/log/netvpn-auth-login.log
CFG
fi

# Limpia clientes dyn_* viejos que podían romper Xray con "User dyn_vip already exists".
if [ -f "$XRAY_CFG" ]; then
python3 - <<'PY_CLEAN' || true
import json, pathlib
cfg=pathlib.Path('/usr/local/etc/xray/config.json')
try:
    data=json.loads(cfg.read_text(errors='ignore'))
except Exception as e:
    print('WARN: no pude leer config xray:', e)
    raise SystemExit(0)
removed=0
for ib in data.get('inbounds', []):
    st=ib.get('settings', {})
    clients=st.get('clients', [])
    if not isinstance(clients, list):
        continue
    clean=[]
    for c in clients:
        email=str(c.get('email',''))
        if email == 'dyn_vip' or email.startswith('dyn_'):
            removed += 1
            continue
        clean.append(c)
    st['clients']=clean
cfg.write_text(json.dumps(data, separators=(',', ':')), encoding='utf-8')
print('Clientes dinámicos viejos eliminados:', removed)
PY_CLEAN
fi

cat > "$STATUS_API" <<'PY_API'
#!/usr/bin/env python3
import json, datetime, os, uuid, hashlib, time, subprocess, shutil, re
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

CONF="/etc/netvpn-auth-login.conf"
SECRET_FILE="/etc/netvpn-auth-login.secret"
XRAY_CFG="/usr/local/etc/xray/config.json"

DYN_PREFIX="dyn_"


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


def yes(v):
    return str(v).lower().strip() in ("1","true","active","activo","on","yes","si")


def normalize_proto(p):
    p=str(p or "").strip().lower()
    if p in ("xray","v2ray","vmess","vless"): return "xray"
    if p in ("sing","sing-box","singbox"): return "singbox"
    if p == "ssh": return "ssh"
    return "xray"


def xray_kind(data):
    k=str(data.get('xray_type') or data.get('xrayKind') or data.get('v2ray_type') or data.get('core_protocol') or data.get('xray_protocol') or data.get('type') or '').strip().lower()
    if k in ('vless','vmess'):
        return k
    # Si no manda tipo, registramos en VMess y VLESS para evitar "invalid user".
    return 'both'


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
    if (not saved_hwid or saved_hwid == 'SIN-HWID') and hwid:
        rows[found_i][2]=hwid; saved_hwid=hwid; bound_now=True; rewrite_db(db,rows)
    hwid_ok=(not saved_hwid) or saved_hwid in ("*", "SIN-HWID") or (hwid and saved_hwid==hwid)
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


def safe_email(uuid_value, tag):
    tag=re.sub(r'[^A-Za-z0-9_\-]+','_', str(tag or 'xray'))[:24]
    return f"{DYN_PREFIX}{uuid_value.replace('-','')[:12]}_{tag}"


def inbound_matches(ib, wanted):
    proto=str(ib.get('protocol','')).lower()
    if wanted == 'both':
        return proto in ('vmess','vless')
    return proto == wanted


def register_xray_uuid(uuid_value, data):
    cfg_path=Path(XRAY_CFG)
    if not cfg_path.exists():
        return {"registered":False,"reason":"xray_config_missing","path":XRAY_CFG}

    wanted=xray_kind(data)
    try:
        original=cfg_path.read_text(errors='ignore')
        conf=json.loads(original)
    except Exception as e:
        return {"registered":False,"reason":"xray_config_read_error","error":str(e),"path":XRAY_CFG}

    changed=False
    added=[]
    # No borra todos los dyn_* para no tumbar otros usuarios activos; solo evita duplicados exactos por id/email en cada inbound.
    for ib in conf.get('inbounds', []):
        if not inbound_matches(ib, wanted):
            continue
        proto=str(ib.get('protocol','')).lower()
        tag=str(ib.get('tag') or f"{proto}_{ib.get('port','')}")
        st=ib.setdefault('settings', {})
        clients=st.setdefault('clients', [])
        if not isinstance(clients, list):
            continue
        email=safe_email(uuid_value, tag)
        # Limpia duplicado exacto del mismo UUID o mismo email en ese inbound.
        new_clients=[]
        for c in clients:
            if c.get('id') == uuid_value or c.get('email') == email:
                changed=True
                continue
            new_clients.append(c)
        client={"id":uuid_value,"email":email}
        if proto == 'vmess':
            client["alterId"] = 0
        new_clients.append(client)
        st['clients']=new_clients
        added.append({"tag":tag,"protocol":proto,"email":email})
        changed=True

    if not added:
        return {"registered":False,"reason":"no_matching_xray_inbound","wanted":wanted,"path":XRAY_CFG}

    backup=f"{XRAY_CFG}.bak_v7e_api_{int(time.time())}"
    try:
        shutil.copy2(XRAY_CFG, backup)
        cfg_path.write_text(json.dumps(conf, separators=(',', ':')), encoding='utf-8')
    except Exception as e:
        return {"registered":False,"reason":"xray_config_write_error","error":str(e),"path":XRAY_CFG}

    # Reinicia Xray para cargar UUID. Si falla, restaura backup.
    cmds=[['systemctl','restart','xray'], ['service','xray','restart']]
    last_err=''
    for cmd in cmds:
        try:
            r=subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=12)
            if r.returncode == 0:
                return {"registered":True,"xray_restarted":True,"added":added,"backup":backup,"wanted":wanted}
            last_err=(r.stderr or r.stdout or '').strip()
        except Exception as e:
            last_err=str(e)
    try:
        shutil.copy2(backup, XRAY_CFG)
        subprocess.run(['systemctl','restart','xray'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=12)
    except Exception:
        pass
    return {"registered":False,"reason":"xray_restart_failed","error":last_err,"backup_restored":backup,"added":added}


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

    allowed="all"; cliente="FREE"; days=-1
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

    now=int(time.time()); bucket=now//300
    seed="|".join([read_secret(), auth, mode, token if mode=="vip" else "free", hwid, proto, str(bucket)])
    u=str(uuid.uuid5(uuid.NAMESPACE_URL, seed))
    password=hashlib.sha256((seed+"|pass").encode()).hexdigest()[:32]

    reg={"registered":False,"reason":"not_required"}
    if proto == 'xray':
        reg=register_xray_uuid(u, data)
        if not reg.get('registered'):
            return {"ok":False,"active":True,"valid":True,"reason":"xray_register_failed","message":"UUID generado pero no se pudo registrar en Xray","uuid":u,"id":u,"register":reg,"mode":mode,"proto":proto,"cliente":cliente,"days_left":days}

    return {
        "ok": True, "active": True, "valid": True,
        "mode": mode, "proto": proto, "allowed_proto": allowed,
        "cliente": cliente, "days_left": days,
        "auth": auth, "host": auth,
        "uuid": u, "id": u, "password": password, "user": u,
        "expires_in": 300, "expires_at": now + (300 - (now % 300)),
        "dynamic": True, "template_only": False,
        "registered": reg.get('registered', False), "register": reg
    }


class H(BaseHTTPRequestHandler):
    def log_message(self,*a): return
    def do_OPTIONS(self): send(self,200,{"ok":True})
    def do_GET(self):
        u=urlparse(self.path); q=parse_qs(u.query); data={k:(v[0] if v else "") for k,v in q.items()}; cfg=read_conf(); auth=cfg.get("AUTH_LIST","")
        if u.path in ("/","/health","/heartbeat"):
            send(self,200,{"ok":True,"service":"netvpn-auth-status-api","version":"V7E_XRAY_REGISTER","port":5000,"auth":auth,"free_enabled":cfg.get("FREE_ENABLED","1")}); return
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

# Instala/asegura servicio systemd para que el API correcto quede en memoria.
cat > "$SERVICE" <<SERVICE_UNIT
[Unit]
Description=NETVPN Auth Status API V7E
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $STATUS_API
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE_UNIT

systemctl daemon-reload 2>/dev/null || true
pkill -f "$STATUS_API" 2>/dev/null || true
sleep 1
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable netvpn-auth-status-api.service 2>/dev/null || true
  systemctl restart netvpn-auth-status-api.service 2>/dev/null || true
fi

if ! ss -ltnp 2>/dev/null | grep -q ':5000'; then
  nohup python3 "$STATUS_API" >/var/log/netvpn-auth-status-api.log 2>&1 &
  sleep 1
fi

systemctl restart xray 2>/dev/null || service xray restart 2>/dev/null || true

cat <<'OKMSG'
OK: FIX_NETVPN_PROTO_CREDENTIAL_XRAY_REGISTER_V7E instalado.

Ahora prueba:
  curl -s http://127.0.0.1:5000/health

Debe decir:
  "version": "V7E_XRAY_REGISTER"

Prueba credencial:
  curl -s -X POST http://127.0.0.1:5000/proto/credential \
    -H 'Content-Type: application/json' \
    -d '{"mode":"vip","token":"cca7bb236bbedc40","hwid":"cca7bb236bbedc40","proto":"xray"}'

Debe responder:
  "ok": true
  "registered": true
  "template_only": false
OKMSG
