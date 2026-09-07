#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - 00-common.sh
# Shared colors/paths/ports. Har module isko sabse pehle source karta hai.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="RareTriccks VPN Panel (Auth Fixed)"
PANEL_VERSION="2026-09-modular"
BANNER_FILE="/etc/issue.net"
DOMAIN_FILE="/etc/raretriccks/domain.conf"
WILDCARD_FILE="/etc/raretriccks/wildcard.conf"
USERS_DIR="/etc/raretriccks/users"
V2USERS_DIR="/etc/raretriccks/v2users"
NGINX_CONF="/etc/nginx/conf.d/raretriccks.conf"
NGINX_STREAM_CONF="/etc/nginx/stream.d/raretriccks-stream.conf"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_ACCESS_LOG="/var/log/xray/access.log"
XRAY_API_ADDR="127.0.0.1:10085"
XRAY_SVC_USER="xray-svc"
XRAY_CERT_DIR="/etc/xray/certs"
XRAY_CERT_FILE="${XRAY_CERT_DIR}/fullchain.pem"
XRAY_KEY_FILE="${XRAY_CERT_DIR}/privkey.pem"

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_PRIVKEY="${SLOWDNS_DIR}/server.key"
SLOWDNS_PUBKEY="${SLOWDNS_DIR}/server.pub"
SLOWDNS_NS_FILE="${SLOWDNS_DIR}/ns_domain.conf"
SLOWDNS_BIN="/usr/local/bin/dns-server"
SLOWDNS_UDP_PORT=53
SLOWDNS_FORWARD_HOST="127.0.0.1"
SLOWDNS_FORWARD_PORT=109

# ---------------- Ports ----------------
WS_SSH_PORT=2082            # Python ws-proxy.py (SSH-WS), 0.0.0.0 - fronted by Nginx on 80/443
V2RAY_WS_PATH="/v2ray"
V2RAY_XHTTP_PATH="/vless-xhttp"
V2RAY_GRPC_SERVICE="vless-grpc"

XRAY_WS_TLS_PORT=20001      # Xray VLESS-WS internal (behind Nginx 443, via real-IP relay)
XRAY_WS_PLAIN_PORT=20002    # Xray VLESS-WS internal (behind Nginx 80, via real-IP relay)
XRAY_GRPC_PORT=20005        # Xray VLESS-gRPC, direct (out of scope for this Nginx pass)
XRAY_XHTTP_PORT=8443        # Xray VLESS-XHTTP(auto) - now 127.0.0.1 only, public via Nginx STREAM
XRAY_TCP_PLAIN_PORT=8880    # Xray VLESS-TCP plain, direct (out of scope for this Nginx pass)
XRAY_TCP_TLS_PORT=8444      # Xray VLESS-TCP+TLS - now 127.0.0.1 only, public via Nginx STREAM

# Real-IP relay ports (Nginx -> relay -> Xray WS, injects PROXY protocol so Xray logs the
# real client IP instead of 127.0.0.1). See 05-realip-tracker.sh + 06-xray-core.sh.
V2RAY_RELAY_TLS_PORT=21001
V2RAY_RELAY_PLAIN_PORT=21002

BADVPN_PORT=7300

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Yeh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
   exit 1
fi

mesg n 2>/dev/null
true

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        cat "$DOMAIN_FILE" | tr -d '\r\n'
    else
        echo "No Domain Set"
    fi
}

get_cert_domain() {
    if [[ -s "$WILDCARD_FILE" ]]; then
        cat "$WILDCARD_FILE" | tr -d '\r\n'
    else
        get_domain
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local label="$3"
    local timeout="${4:-15}"
    local waited=0

    while ! (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; do
        sleep 1
        waited=$((waited+1))
        if [[ $waited -ge $timeout ]]; then
            echo -e "${RED}[WARN] ${label} (${host}:${port}) did not come up after ${timeout}s${NC}" >&2
            return 1
        fi
    done
    exec 3>&- 2>/dev/null
    echo -e "${GREEN}[OK] ${label} listening on ${host}:${port}${NC}" >&2
    return 0
}
