#!/usr/bin/env bash
set -e

TARGET="/usr/local/bin/netvpn-vip"
CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"

mkdir -p /etc
[ -f "$TARGET" ] && cp -a "$TARGET" "$TARGET.bak_v7_simple_$(date +%F_%H%M%S)" || true

touch "$VIP_DB" "$LOG"
perl -pi -e 's/\x00//g' "$VIP_DB" 2>/dev/null || true
chmod 600 "$VIP_DB" "$LOG" 2>/dev/null || true

cat > "$TARGET" <<'SH'
#!/usr/bin/env bash
set -e

CONF="/etc/netvpn-auth-login.conf"
VIP_DB="/etc/netvpn-vip.tokens"
LOG="/var/log/netvpn-auth-login.log"

C0='\033[0m'; B='\033[1m'; R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'; M='\033[1;35m'; W='\033[1;37m'; GR='\033[0;32m'

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
count_expired(){ safe_lines | while IFS='|' read -r token exp hwid st name rest; do d="$(days_left "$exp")"; [ "$d" -lt 0 ] && echo x; done | wc -l | tr -d ' '; }
online_count(){ ss -tn state established '( sport = :2290 or sport = :90 or sport = :80 )' 2>/dev/null | tail -n +2 | wc -l | tr -d ' '; }

pause(){ echo; read -rp "ENTER para continuar..." _; }

print_header(){
  clear
  echo -e "${G}============================================================${C0}"
  echo -e "      🔐 ${W}NETVPN AUTH LOGIN - MANAGER V7B${C0}"
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
  ensure_files
  echo -e "${G}--------------------------------------------------------------------------------${C0}"
  printf "%b\n" "${W} #   TOKEN              CLIENTE             VENCE       DIAS   ESTADO       HWID${C0}"
  echo -e "${G}--------------------------------------------------------------------------------${C0}"
  local i=0 any=0
  while IFS='|' read -r token exp hwid st name rest; do
    [ -z "$token" ] && continue
    any=1; i=$((i+1))
    [ -z "$name" ] && name="Cliente VIP"
    [ -z "$hwid" ] && hwid="SIN-HWID"
    d="$(days_left "$exp")"
    estado="$(status_color "$st" "$exp")"
    if [ "$hwid" = "*" ] || [ "$hwid" = "SIN-HWID" ]; then hwid_show="${Y}${hwid}${C0}"; else hwid_show="${C}${hwid:0:12}...${C0}"; fi
    if [ "$d" -lt 0 ]; then dshow="${R}${d}${C0}"; else dshow="${G}${d}${C0}"; fi
    printf "%b" "${Y}[$i]${C0} "
    printf "%-18s %-19s %-10s " "$token" "${name:0:19}" "$exp"
    printf "%b " "$dshow"
    printf "%b " "$estado"
    printf "%b\n" "$hwid_show"
  done < <(safe_lines)
  [ "$any" = "0" ] && echo -e "${Y}Sin tokens VIP todavía.${C0}"
  echo -e "${G}--------------------------------------------------------------------------------${C0}"
}

token_by_num(){
  local n="$1" i=0 token
  while IFS='|' read -r token exp hwid st name rest; do
    [ -z "$token" ] && continue
    i=$((i+1))
    if [ "$i" = "$n" ]; then echo "$token"; return 0; fi
  done < <(safe_lines)
  return 1
}

choose_token(){
  # IMPORTANTE: esta función se usa dentro de token="$(choose_token)".
  # Por eso la tabla y el prompt deben ir a /dev/tty; si van a stdout,
  # bash los captura y no se muestran en pantalla.
  print_tokens > /dev/tty
  echo > /dev/tty
  printf "Elige número: " > /dev/tty
  read -r n < /dev/tty
  token_by_num "$n"
}

rewrite_token_field(){
  local token="$1" field="$2" value="$3"
  awk -F'|' -v T="$token" -v F="$field" -v V="$value" 'BEGIN{OFS="|"} $1==T{$F=V} {print}' "$VIP_DB" > /tmp/netvpn-vip.tokens
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
}

add_token(){
  ensure_files
  echo -e "${C}Crear / renovar VIP${C0}"
  read -rp "Token: " token
  read -rp "Días: " days
  read -rp "Cliente: " name
  [ -z "$days" ] && days=30
  [ -z "$name" ] && name="Cliente VIP"
  [ -z "$token" ] && { echo -e "${R}Token vacío.${C0}"; pause; return; }
  exp="$(date -d "+${days} days" +%F)"
  grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true
  mv /tmp/netvpn-vip.tokens "$VIP_DB"
  echo "${token}|${exp}||active|${name}" >> "$VIP_DB"
  chmod 600 "$VIP_DB" 2>/dev/null || true
  echo -e "${G}OK creado: $token vence $exp. HWID: primer uso.${C0}"
  pause
}

block_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { rewrite_token_field "$token" 4 "blocked"; echo -e "${G}OK bloqueado.${C0}"; }; pause; }
active_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { rewrite_token_field "$token" 4 "active"; echo -e "${G}OK activo.${C0}"; }; pause; }
del_token(){ token="$(choose_token || true)"; [ -n "$token" ] && { grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo -e "${G}OK eliminado.${C0}"; }; pause; }
renew_token(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "Días nuevos: " d; [ -z "$d" ] && d=30; exp="$(date -d "+${d} days" +%F)"; rewrite_token_field "$token" 2 "$exp"; rewrite_token_field "$token" 4 "active"; echo -e "${G}OK renovado hasta $exp.${C0}"; pause; }
rename_token(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "Nuevo cliente: " name; [ -z "$name" ] && name="Cliente VIP"; rewrite_token_field "$token" 5 "$name"; echo -e "${G}OK nombre cambiado.${C0}"; pause; }
bind_hwid(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; read -rp "HWID: " hw; rewrite_token_field "$token" 3 "$hw"; echo -e "${G}OK HWID vinculado.${C0}"; pause; }
reset_hwid(){ token="$(choose_token || true)"; [ -z "$token" ] && { pause; return; }; rewrite_token_field "$token" 3 ""; echo -e "${G}OK HWID reseteado. Se vinculará al primer uso.${C0}"; pause; }

status_api(){
  echo -e "${C}API 5000:${C0}"
  curl -s http://127.0.0.1:5000/health || true
  echo
  echo -e "${C}FREE:${C0}"
  curl -s 'http://127.0.0.1:5000/checkUser?mode=free' || true
  echo
  echo -e "${C}Servicios:${C0}"
  systemctl is-active netvpn-auth-status-api.service 2>/dev/null || true
  systemctl is-active svrcode-ssh-payload.service 2>/dev/null || true
  pause
}

show_logs(){ tail -80 "$LOG" 2>/dev/null || echo "Sin log"; pause; }
open_gen(){
  if command -v gen >/dev/null 2>&1; then gen; return; fi
  if command -v svrcode >/dev/null 2>&1; then svrcode; return; fi
  if [ -x /opt/svrcode/menu.sh ]; then bash /opt/svrcode/menu.sh; return; fi
  echo -e "${Y}No encontré comando GEN original. Abre el menú original de protocolos.${C0}"
  pause
}

menu(){
  ensure_files
  while true; do
    print_header
    echo -e "${M}📌 MENÚ PRINCIPAL${C0}"
    echo -e "${G}------------------------------------------------------------${C0}"
    echo -e "${Y}[1]${C0}  ➕ Crear / renovar VIP"
    echo -e "${Y}[2]${C0}  📋 Listar"
    echo -e "${Y}[3]${C0}  ⛔ Bloquear"
    echo -e "${Y}[4]${C0}  ✅ Activar"
    echo -e "${Y}[5]${C0}  🗑️  Eliminar"
    echo -e "${Y}[6]${C0}  🔄 Renovar"
    echo -e "${Y}[7]${C0}  ✏️  Cambiar nombre"
    echo -e "${Y}[8]${C0}  📱 Vincular HWID"
    echo -e "${Y}[9]${C0}  ♻️  Resetear HWID"
    echo -e "${Y}[10]${C0} 🔴 Apagar FREE"
    echo -e "${Y}[11]${C0} 🟢 Encender FREE"
    echo -e "${Y}[12]${C0} 🛠️  Estado API"
    echo -e "${Y}[13]${C0} ⚙️  GEN / Métodos"
    echo -e "${Y}[14]${C0} 📜 Logs AUTH"
    echo -e "${Y}[0]${C0}  🚪 Salir"
    echo -e "${G}------------------------------------------------------------${C0}"
    read -rp "Elige opción: " op
    case "$op" in
      1) add_token ;;
      2) print_tokens; pause ;;
      3) block_token ;;
      4) active_token ;;
      5) del_token ;;
      6) renew_token ;;
      7) rename_token ;;
      8) bind_hwid ;;
      9) reset_hwid ;;
      10) set_free 0; echo -e "${G}FREE apagado.${C0}"; pause ;;
      11) set_free 1; echo -e "${G}FREE encendido.${C0}"; pause ;;
      12) status_api ;;
      13) open_gen ;;
      14) show_logs ;;
      0) exit 0 ;;
      *) echo -e "${R}Opción inválida.${C0}"; sleep 1 ;;
    esac
  done
}

ensure_files
cmd="${1:-menu}"; shift || true
case "$cmd" in
  menu) menu ;;
  list) print_tokens ;;
  add) token="$1"; days="${2:-30}"; name="${3:-Cliente VIP}"; exp="$(date -d "+${days} days" +%F)"; grep -v "^${token}|" "$VIP_DB" > /tmp/netvpn-vip.tokens 2>/dev/null || true; mv /tmp/netvpn-vip.tokens "$VIP_DB"; echo "${token}|${exp}||active|${name}" >> "$VIP_DB"; echo "OK $token $exp" ;;
  free-on) set_free 1; echo "FREE ON" ;;
  free-off) set_free 0; echo "FREE OFF" ;;
  status) status_api ;;
  gen) open_gen ;;
  *) echo "Uso: netvpn-vip menu|list|add|free-on|free-off|status|gen" ;;
esac
SH

chmod +x "$TARGET"

# svrtoken abre el gestor correcto
cat >/usr/local/bin/svrtoken <<'SH'
#!/usr/bin/env bash
exec /usr/local/bin/netvpn-vip menu
SH
chmod +x /usr/local/bin/svrtoken

# comando corto para gen si no existe
if [ ! -x /usr/local/bin/netvpn-gen ]; then
cat >/usr/local/bin/netvpn-gen <<'SH'
#!/usr/bin/env bash
if command -v gen >/dev/null 2>&1; then exec gen; fi
if command -v svrcode >/dev/null 2>&1; then exec svrcode; fi
if [ -x /opt/svrcode/menu.sh ]; then exec bash /opt/svrcode/menu.sh; fi
echo "No encontré el menú original GEN / métodos."
SH
chmod +x /usr/local/bin/netvpn-gen
fi

echo "OK: netvpn-vip V7B instalado. Lista visible en activar/bloquear/eliminar."
echo "Abrir: netvpn-vip menu"
