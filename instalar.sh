#!/usr/bin/env bash
set -euo pipefail

# NETVPN VIP MANAGER MENU V6
# Mejora visual tipo SVRCODE original:
# - Iconos/colores
# - Estadisticas arriba: total, activos, vencidos, bloqueados, FREE, online
# - Operaciones por numero de lista, no pide pegar token
# - Opcion GEN / Metodos: intenta abrir menu/generador original si existe
# - No toca protocolos, payload, bridge, ssh ni app

MANAGER="/usr/local/bin/netvpn-vip"
BACKUP="/usr/local/bin/netvpn-vip.bak_menu_v6_$(date +%F_%H%M%S)"

if [ -f "$MANAGER" ]; then
  cp -a "$MANAGER" "$BACKUP"
fi

cat > "$MANAGER" <<'SH'
#!/usr/bin/env bash
set -u

CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"
API_SERVICE="netvpn-auth-status-api.service"
PAYLOAD_SERVICE="svrcode-ssh-payload.service"

# Colores
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; M='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'

line(){ echo -e "${G}════════════════════════════════════════════════════════════${N}"; }
sep(){ echo -e "${C}────────────────────────────────────────────────────────────${N}"; }
pause(){ echo; read -rp "Presiona ENTER para continuar..." _; }

ensure_files(){
  mkdir -p /etc
  touch "$VIP_DB" "$LOG"
  chmod 600 "$VIP_DB" "$LOG" 2>/dev/null || true
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<CFG
AUTH_LIST=localhost
FREE_ENABLED=1
VIP_DB=$VIP_DB
LOG=$LOG
CFG
  fi
  grep -q '^VIP_DB=' "$CONF" 2>/dev/null || echo "VIP_DB=$VIP_DB" >> "$CONF"
  grep -q '^LOG=' "$CONF" 2>/dev/null || echo "LOG=$LOG" >> "$CONF"
  grep -q '^FREE_ENABLED=' "$CONF" 2>/dev/null || echo "FREE_ENABLED=1" >> "$CONF"
}

get_conf(){ grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2-; }
set_conf(){
  local k="$1" v="$2"
  ensure_files
  if grep -q "^${k}=" "$CONF"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$CONF"
  else
    echo "${k}=${v}" >> "$CONF"
  fi
}

auth(){ get_conf AUTH_LIST | awk '{print $1}'; }
free_enabled(){ get_conf FREE_ENABLED; }

normalize_date(){
  local d="$1"
  date -d "$d" +%F 2>/dev/null || echo "$d"
}

days_left(){
  local exp="$1"
  local now exp_s
  now=$(date +%s)
  exp_s=$(date -d "$exp" +%s 2>/dev/null || echo 0)
  if [ "$exp_s" -eq 0 ]; then echo -999; return; fi
  echo $(( (exp_s - now) / 86400 ))
}

state_color(){
  local st="${1,,}" exp="$2" days
  days=$(days_left "$exp")
  if [[ "$st" =~ ^(blocked|block|bloqueado|inactive|off|0)$ ]]; then echo -e "${R}${st}${N}"; return; fi
  if [ "$days" -lt 0 ]; then echo -e "${R}vencido${N}"; return; fi
  if [[ "$st" =~ ^(active|activo|on|1|true)$ ]]; then echo -e "${G}activo${N}"; return; fi
  echo -e "${Y}${st}${N}"
}

free_color(){
  local f="$(free_enabled)"
  if [[ "${f,,}" =~ ^(1|true|active|activo|on|yes|si)$ ]]; then echo -e "${G}ON${N}"; else echo -e "${R}OFF${N}"; fi
}

token_stats(){
  local total=0 active=0 expired=0 blocked=0 unbound=0
  local t exp hwid st cli d
  while IFS='|' read -r t exp hwid st cli rest; do
    [ -z "${t:-}" ] && continue
    [[ "$t" =~ ^# ]] && continue
    total=$((total+1))
    d=$(days_left "$exp")
    if [[ "${st,,}" =~ ^(blocked|block|bloqueado|inactive|off|0)$ ]]; then blocked=$((blocked+1));
    elif [ "$d" -lt 0 ]; then expired=$((expired+1));
    else active=$((active+1)); fi
    if [ -z "${hwid:-}" ]; then unbound=$((unbound+1)); fi
  done < "$VIP_DB"
  echo "$total|$active|$expired|$blocked|$unbound"
}

online_count(){
  # Cuenta aproximada de sesiones del usuario tecnico nvp_<auth>.
  local a u
  a="$(auth)"
  [ -z "$a" ] && { echo 0; return; }
  u="$(python3 - <<PY 2>/dev/null
import hashlib
print('nvp_' + hashlib.sha256('$a'.encode()).hexdigest()[:12])
PY
)"
  pgrep -u "$u" 2>/dev/null | wc -l | tr -d ' '
}

header(){
  clear
  ensure_files
  local stats total active expired blocked unbound online
  IFS='|' read -r total active expired blocked unbound <<<"$(token_stats)"
  online="$(online_count)"
  line
  echo -e "${W}        🔐 NETVPN AUTH LOGIN - TOKEN MANAGER V6${N}"
  line
  echo -e "🌐 AUTH : ${C}$(auth)${N}"
  echo -e "🟢 FREE : $(free_color)       👥 Online: ${Y}${online}${N}"
  echo -e "🎫 Tokens: ${W}${total}${N}   ✅ Activos: ${G}${active}${N}   ⛔ Bloq: ${R}${blocked}${N}   ⏳ Vencidos: ${R}${expired}${N}   📱 Sin HWID: ${Y}${unbound}${N}"
  line
}

list_tokens(){
  ensure_files
  header
  echo -e "${W}📋 LISTA DE TOKENS VIP${N}"
  sep
  printf "${C}%-4s %-18s %-18s %-12s %-8s %-10s %-16s${N}\n" "N°" "TOKEN" "CLIENTE" "VENCE" "DÍAS" "ESTADO" "HWID"
  sep
  local n=0 t exp hwid st cli rest d state hwshow
  while IFS='|' read -r t exp hwid st cli rest; do
    [ -z "${t:-}" ] && continue
    [[ "$t" =~ ^# ]] && continue
    n=$((n+1))
    cli="${cli:-Cliente VIP}"
    d=$(days_left "$exp")
    state=$(state_color "${st:-active}" "$exp")
    if [ -z "${hwid:-}" ]; then hwshow="${Y}primer uso${N}"; elif [ "$hwid" = "*" ]; then hwshow="${Y}libre(*)${N}"; else hwshow="${G}${hwid:0:14}${N}"; fi
    if [ "$d" -lt 0 ]; then d="${R}${d}${N}"; else d="${G}${d}${N}"; fi
    printf "%-4s ${Y}%-18s${N} %-18s %-12s %-17b %-18b %-16b\n" "$n" "$t" "$cli" "$exp" "$d" "$state" "$hwshow"
  done < "$VIP_DB"
  if [ "$n" -eq 0 ]; then echo -e "${Y}Sin tokens todavía.${N}"; fi
  sep
}

get_token_by_num(){
  local num="$1" n=0 t exp hwid st cli rest
  while IFS='|' read -r t exp hwid st cli rest; do
    [ -z "${t:-}" ] && continue
    [[ "$t" =~ ^# ]] && continue
    n=$((n+1))
    if [ "$n" = "$num" ]; then echo "$t"; return 0; fi
  done < "$VIP_DB"
  return 1
}

require_num_token(){
  list_tokens
  local num token
  echo
  read -rp "Elige número de token: " num
  token="$(get_token_by_num "$num" || true)"
  if [ -z "$token" ]; then echo -e "${R}Número inválido.${N}"; pause; return 1; fi
  echo "$token"
}

add_token(){
  ensure_files
  header
  echo -e "${W}➕ CREAR / RENOVAR TOKEN VIP${N}"
  sep
  local token days cli hwid exp
  read -rp "Token: " token
  [ -z "$token" ] && { echo -e "${R}Token vacío.${N}"; pause; return; }
  read -rp "Días [30]: " days
  [ -z "$days" ] && days=30
  read -rp "Cliente: " cli
  [ -z "$cli" ] && cli="Cliente VIP"
  read -rp "HWID opcional (ENTER = primer uso): " hwid
  exp="$(date -d "+${days} days" +%F)"
  grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  echo "${token}|${exp}|${hwid}|active|${cli}" >> "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
  echo -e "${G}OK token guardado.${N}"
  echo -e "Token: ${Y}$token${N}  Cliente: ${C}$cli${N}  Vence: ${G}$exp${N}"
  [ -z "$hwid" ] && echo -e "HWID: ${Y}se vinculará al primer uso${N}" || echo -e "HWID: ${G}$hwid${N}"
  pause
}

update_token_field(){
  local token="$1" field="$2" value="$3"
  awk -F'|' -v T="$token" -v F="$field" -v V="$value" 'BEGIN{OFS="|"} $1==T{$F=V} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
}

block_token(){ local token; token="$(require_num_token)" || return; update_token_field "$token" 4 "blocked"; echo -e "${R}Bloqueado:${N} $token"; pause; }
active_token(){ local token; token="$(require_num_token)" || return; update_token_field "$token" 4 "active"; echo -e "${G}Activo:${N} $token"; pause; }
del_token(){ local token; token="$(require_num_token)" || return; grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo -e "${R}Eliminado:${N} $token"; pause; }
renew_token(){
  local token days exp
  token="$(require_num_token)" || return
  read -rp "Agregar/renovar por cuántos días: " days
  [ -z "$days" ] && days=30
  exp="$(date -d "+${days} days" +%F)"
  update_token_field "$token" 2 "$exp"
  update_token_field "$token" 4 "active"
  echo -e "${G}Renovado:${N} $token vence $exp"
  pause
}
rename_token(){ local token cli; token="$(require_num_token)" || return; read -rp "Nuevo nombre cliente: " cli; [ -z "$cli" ] && return; update_token_field "$token" 5 "$cli"; echo -e "${G}Nombre actualizado.${N}"; pause; }
bind_hwid(){ local token hwid; token="$(require_num_token)" || return; read -rp "HWID real: " hwid; [ -z "$hwid" ] && { echo "HWID vacío"; pause; return; }; update_token_field "$token" 3 "$hwid"; echo -e "${G}HWID vinculado.${N}"; pause; }
reset_hwid(){ local token; token="$(require_num_token)" || return; update_token_field "$token" 3 ""; echo -e "${Y}HWID reseteado. Se vinculará al primer uso.${N}"; pause; }

free_on(){ set_conf FREE_ENABLED 1; echo -e "${G}FREE encendido.${N}"; pause; }
free_off(){ set_conf FREE_ENABLED 0; echo -e "${R}FREE apagado.${N}"; pause; }

status_api(){
  header
  echo -e "${W}🩺 ESTADO API / SERVICIOS${N}"
  sep
  echo -e "${C}Config:${N}"; cat "$CONF" 2>/dev/null || true
  echo
  echo -e "${C}Puerto 5000:${N}"; ss -ltnp 2>/dev/null | grep ':5000' || echo "5000 no escucha"
  echo
  echo -e "${C}Health:${N}"; curl -s http://127.0.0.1:5000/health 2>/dev/null || echo "sin respuesta"
  echo
  echo -e "${C}Servicios:${N}"
  systemctl is-active --quiet "$API_SERVICE" && echo -e "API 5000: ${G}active${N}" || echo -e "API 5000: ${R}inactive${N}"
  systemctl is-active --quiet "$PAYLOAD_SERVICE" && echo -e "Bridge: ${G}active${N}" || echo -e "Bridge: ${R}inactive${N}"
  pause
}

logs(){
  header
  echo -e "${W}📜 ÚLTIMOS LOGS AUTH${N}"
  sep
  tail -80 "$LOG" 2>/dev/null || echo "Sin log"
  pause
}

open_gen(){
  header
  echo -e "${W}⚙️ GEN / MÉTODOS ORIGINAL${N}"
  sep
  echo "Buscando generador/menu original..."
  echo

  # Rutas/comandos comunes, sin borrar nada.
  local candidates=()
  command -v svrcode >/dev/null 2>&1 && candidates+=("$(command -v svrcode)")
  command -v menu >/dev/null 2>&1 && candidates+=("$(command -v menu)")
  command -v gen >/dev/null 2>&1 && candidates+=("$(command -v gen)")
  [ -f /opt/svrcode/neon_dashboard.py ] && candidates+=("python3 /opt/svrcode/neon_dashboard.py")
  [ -f /opt/svrcode/gen.py ] && candidates+=("python3 /opt/svrcode/gen.py")
  [ -f /root/gerador.sh ] && candidates+=("bash /root/gerador.sh")
  [ -f /root/generator.sh ] && candidates+=("bash /root/generator.sh")

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo -e "${Y}No encontré comando GEN automático.${N}"
    echo "Archivos parecidos:"
    find /opt /root -maxdepth 4 \( -iname '*gen*' -o -iname '*metod*' -o -iname '*method*' -o -iname '*dashboard*' \) 2>/dev/null | head -30
    pause
    return
  fi

  local i=1
  for c in "${candidates[@]}"; do
    echo "[$i] $c"
    i=$((i+1))
  done
  echo "[0] Volver"
  echo
  local op cmd
  read -rp "Elige GEN/Métodos: " op
  [ "$op" = "0" ] && return
  if ! [[ "$op" =~ ^[0-9]+$ ]] || [ "$op" -lt 1 ] || [ "$op" -gt "${#candidates[@]}" ]; then
    echo "Opción inválida"; pause; return
  fi
  cmd="${candidates[$((op-1))]}"
  echo -e "${G}Abriendo:${N} $cmd"
  sleep 1
  eval "$cmd"
}

menu(){
  ensure_files
  while true; do
    header
    echo -e "${W}📌 MENÚ PRINCIPAL${N}"
    sep
    echo -e " ${G}[1]${N}  ➕ Crear/Renovar token VIP"
    echo -e " ${G}[2]${N}  📋 Listar tokens con colores"
    echo -e " ${G}[3]${N}  ⛔ Bloquear token por número"
    echo -e " ${G}[4]${N}  ✅ Activar token por número"
    echo -e " ${G}[5]${N}  🗑️  Eliminar token por número"
    echo -e " ${G}[6]${N}  🔄 Renovar token por número"
    echo -e " ${G}[7]${N}  ✏️  Cambiar nombre cliente por número"
    echo -e " ${G}[8]${N}  📱 Vincular token a HWID"
    echo -e " ${G}[9]${N}  ♻️  Resetear HWID para primer uso"
    echo -e "${Y}[10]${N}  🔴 Apagar FREE"
    echo -e "${Y}[11]${N}  🟢 Encender FREE"
    echo -e "${C}[12]${N}  🩺 Estado API / servicios"
    echo -e "${C}[13]${N}  ⚙️  GEN / Métodos original"
    echo -e "${C}[14]${N}  📜 Ver logs AUTH"
    echo -e " ${R}[0]${N}  🚪 Salir"
    sep
    read -rp "Elige opción: " op
    case "$op" in
      1) add_token ;;
      2) list_tokens; pause ;;
      3) block_token ;;
      4) active_token ;;
      5) del_token ;;
      6) renew_token ;;
      7) rename_token ;;
      8) bind_hwid ;;
      9) reset_hwid ;;
      10) free_off ;;
      11) free_on ;;
      12) status_api ;;
      13) open_gen ;;
      14) logs ;;
      0) exit 0 ;;
      *) echo -e "${R}Opción inválida.${N}"; sleep 1 ;;
    esac
  done
}

ensure_files
cmd="${1:-menu}"; shift || true
case "$cmd" in
  menu) menu ;;
  add) add_token "$@" ;;
  list) list_tokens ;;
  block) block_token ;;
  active) active_token ;;
  del|delete|rm) del_token ;;
  renew) renew_token ;;
  bind) bind_hwid ;;
  reset-hwid) reset_hwid ;;
  free-on) set_conf FREE_ENABLED 1; echo "FREE encendido" ;;
  free-off) set_conf FREE_ENABLED 0; echo "FREE apagado" ;;
  status) status_api ;;
  gen|gin) open_gen ;;
  *) echo "Uso: netvpn-vip menu|add|list|block|active|del|renew|bind|reset-hwid|free-on|free-off|status|gen"; exit 1 ;;
esac
SH

chmod +x "$MANAGER"

# svrtoken redirige al nuevo menú bonito
cat > /usr/local/bin/svrtoken <<'SH'
#!/usr/bin/env bash
exec /usr/local/bin/netvpn-vip menu
SH
chmod +x /usr/local/bin/svrtoken

# Alias opcional para escribir gin/gen y abrir la opcion de metodos
cat > /usr/local/bin/netvpn-gen <<'SH'
#!/usr/bin/env bash
exec /usr/local/bin/netvpn-vip gen
SH
chmod +x /usr/local/bin/netvpn-gen

echo "=== LISTO ==="
echo "Backup anterior: $BACKUP"
echo "Abrir menú nuevo: netvpn-vip menu"
echo "También: svrtoken"
echo "GEN/Métodos: netvpn-vip gen  o  netvpn-gen"
