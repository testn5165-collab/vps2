#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 00-common.sh
# Shared config, colors, helper functions. Har module isko source karta hai.
# Usage: source /etc/raretriccks/00-common.sh
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="RARETRICCKS MULTI PROTOCOL"
BASE_DIR="/etc/raretriccks"
DOMAIN_FILE="${BASE_DIR}/domain.conf"
USERS_DIR="${BASE_DIR}/users"
BANNER_FILE="/etc/issue.net"

# ---------------- SSH ----------------
DROPBEAR_PORTS="22 109 8022"       # Direct + WS-backend + backup (447 freed for HAProxy TLS list below)
SSH_WS_INTERNAL_PORT=12082         # ws-proxy.py listens here on 127.0.0.1 ONLY (never public)
SSH_SSL_STUNNEL_PORT=444           # raw SSH wrapped in TLS (non-WS) via stunnel

# Public multi-port SSH-WS list (all of these are HAProxy frontends -> same internal backend).
# Edit these arrays freely; every port here will serve SSH-WS (and V2Ray-WS on the same path scheme).
SSH_WS_TLS_PORTS=(443 2053 2083 2087 2096 8443 445 447 777)
SSH_WS_PLAIN_PORTS=(80 8080 8880 2052 2082 2086 2095)

# ---------------- V2Ray / Xray ----------------
XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_SERVICE_USER="xray"           # dedicated non-login user (NOT "nobody" - shared by too many system procs)
V2RAY_WS_PATH="/v2ray"
V2RAY_XHTTP_PATH="/vless-xhttp"

XRAY_WS_TLS_PORT=20001            # behind HAProxy TLS termination (any port in SSH_WS_TLS_PORTS)
XRAY_WS_PLAIN_PORT=20002          # behind HAProxy plain (any port in SSH_WS_PLAIN_PORTS)
XRAY_XHTTP_PORT=9443              # dedicated, Xray handles its own TLS (moved off 8443 - now a HAProxy port)
XRAY_TCP_PLAIN_PORT=9880          # dedicated, plain (moved off 8880 - now a HAProxy port)
XRAY_TCP_TLS_PORT=9444            # dedicated, Xray handles its own TLS
XRAY_GRPC_PORT=9005               # dedicated, plain

# ---------------- BadVPN UDPGW ----------------
UDPGW_BIND="127.0.0.1"
UDPGW_PORT=7300

mkdir -p "$BASE_DIR" "$USERS_DIR"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Root privilege chahiye (sudo -i)${NC}"
   exit 1
fi

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        cat "$DOMAIN_FILE" | tr -d '\r\n'
    else
        echo "No Domain Set"
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] to continue...${NC}"
    read -r
}

require_domain_or_die() {
    local d
    d=$(get_domain)
    if [[ "$d" == "No Domain Set" || -z "$d" ]]; then
        echo -e "${RED}[ERROR] Pehle domain set karo: echo yourdomain.com > ${DOMAIN_FILE}${NC}"
        exit 1
    fi
    echo "$d"
}

# ---------------------------------------------------------------------------
# ensure_xray_user: dedicated system user banata hai (agar already na ho) jo
# xray.service chalayega. "nobody" use nahi karte kyunki wo bohot saare
# system daemons ke beech shared hota hai - dedicated user isolation ke liye
# better hai aur systemd bhi "Special user nobody configured" warning deta hai.
# Idempotent - baar baar chalane par bhi safe hai.
# ---------------------------------------------------------------------------
ensure_xray_user() {
    if ! id "${XRAY_SERVICE_USER}" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin "${XRAY_SERVICE_USER}"
    fi
}

# ---------------------------------------------------------------------------
# fix_xray_perms: XRAY_CONFIG aur TLS certs dono ko XRAY_SERVICE_USER ke liye
# readable banata hai. Har module jo config.json likhta/badalta hai, isko
# END mein zaroor call kare - warna phir se "permission denied" wapas aa
# jaayega jaise pehle haproxy/nobody mismatch ke time hua tha.
# ---------------------------------------------------------------------------
fix_xray_perms() {
    ensure_xray_user
    if [[ -f "$XRAY_CONFIG" ]]; then
        chown "${XRAY_SERVICE_USER}:${XRAY_SERVICE_USER}" "$XRAY_CONFIG"
        chmod 640 "$XRAY_CONFIG"
    fi
    chmod 755 "$(dirname "$XRAY_CONFIG")" 2>/dev/null || true

    local d
    d=$(get_domain)
    if [[ -d "/etc/letsencrypt/live/${d}" ]]; then
        command -v setfacl &>/dev/null || apt-get install -y acl >/dev/null 2>&1
        setfacl -R -m u:"${XRAY_SERVICE_USER}":rx /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
        setfacl -R -m u:"${XRAY_SERVICE_USER}":r "/etc/letsencrypt/archive/${d}"/*.pem 2>/dev/null || true
    fi

    # systemd drop-in: xray.service ko XRAY_SERVICE_USER se chalao, "nobody" se nahi.
    mkdir -p /etc/systemd/system/xray.service.d
    cat << SVC_OVERRIDE > /etc/systemd/system/xray.service.d/10-service-user.conf
[Service]
User=${XRAY_SERVICE_USER}
Group=${XRAY_SERVICE_USER}
SVC_OVERRIDE
    systemctl daemon-reload
}
