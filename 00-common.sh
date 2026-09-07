#!/bin/bash

# ==============================================================================
# Script Name   : RareTriccks VPN Panel (Dynamic Domain Supported)
# Custom Path   : /raretriccks
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="RareTriccks VPN Panel"
BANNER_FILE="/etc/issue.net"
CUSTOM_PATH="/raretriccks"
DOMAIN_FILE="/etc/raretriccks/domain.conf"

# ---- Xray / V2Ray shared paths & ports ----
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_DIR}/config.json"
XRAY_CERT_DIR="/etc/raretriccks/xray-cert"
XRAY_LOG_DIR="/var/log/xray"
XRAY_SYS_USER="xrayuser"
XRAY_USERS_DIR="/etc/raretriccks/v2ray-users"
V2RAY_WS_PATH="/v2ray"
PORT_WS_INTERNAL=10000
PORT_XHTTP_TLS=9443
PORT_TCP_PLAIN=9880
PORT_TCP_TLS=9444
PORT_GRPC=9005

# ---- Stunnel (SSH-over-SSL) shared ports ----
STUNNEL_PORT=445
STUNNEL_TARGET_PORT=109

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Yeh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
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
    echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

fix_dropbear_core() {
    mkdir -p /etc/dropbear
    chmod 700 /etc/dropbear

    if [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]]; then
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key &>/dev/null
    fi
    if [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]]; then
        dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key &>/dev/null
    fi
    if [[ ! -f /etc/dropbear/dropbear_ed25519_host_key ]]; then
        dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key &>/dev/null
    fi

    chmod 600 /etc/dropbear/*_host_key 2>/dev/null

    # Remove broken override directory to prevent crashes
    rm -rf /etc/systemd/system/dropbear.service.d

    # NOTE: OpenSSH (sshd) already owns port 22. Dropbear must NOT also bind
    # port 22 or one of the two services will fail to start / silently die,
    # breaking SSH Direct + SSH-WS + Xray at once. Dropbear only serves its
    # extra ports (109, 447) here; port 22 stays with OpenSSH.
    cat << 'DB_CONF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 447 -b /etc/issue.net"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DB_CONF

    # Make sure OpenSSH itself is alive and listening on 22 (used by SSH
    # Direct and as the tunnel target for stunnel/SSH-over-SSL).
    systemctl enable ssh 2>/dev/null
    systemctl restart ssh 2>/dev/null

    systemctl daemon-reload
    systemctl enable dropbear
    systemctl restart dropbear
}

# Copies the current Let's Encrypt cert for the active domain into every
# component that needs its own local copy (Xray, stunnel), fixes ownership,
# and reloads the relevant services. Safe to call any time (no-op if no
# domain/cert yet). Called by setup_ssl and by the certbot renewal hook.
sync_all_certs() {
    local dom=$(get_domain)
    [[ "$dom" == "No Domain Set" || -z "$dom" ]] && return
    [[ -f "/etc/letsencrypt/live/${dom}/fullchain.pem" ]] || return

    if id -u "$XRAY_SYS_USER" &>/dev/null; then
        mkdir -p "$XRAY_CERT_DIR"
        cp -L "/etc/letsencrypt/live/${dom}/fullchain.pem" "${XRAY_CERT_DIR}/fullchain.pem"
        cp -L "/etc/letsencrypt/live/${dom}/privkey.pem" "${XRAY_CERT_DIR}/privkey.pem"
        chown -R "${XRAY_SYS_USER}:${XRAY_SYS_USER}" "$XRAY_CERT_DIR"
        chmod 600 "${XRAY_CERT_DIR}"/*.pem
        systemctl restart xray 2>/dev/null
    fi

    if [[ -d /etc/stunnel ]] && command -v stunnel4 &>/dev/null; then
        cat "/etc/letsencrypt/live/${dom}/fullchain.pem" "/etc/letsencrypt/live/${dom}/privkey.pem" > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem
        systemctl restart stunnel4 2>/dev/null
    fi
}

# Installs a certbot deploy-hook so every future auto-renewal keeps Nginx,
# Xray and stunnel certs in sync automatically (no manual step needed).
install_cert_renew_hook() {
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat << 'HOOK_EOF' > /etc/letsencrypt/renewal-hooks/deploy/raretriccks-sync.sh
#!/bin/bash
source /etc/raretriccks/00-common.sh
sync_all_certs
systemctl restart nginx 2>/dev/null
HOOK_EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/raretriccks-sync.sh
}

